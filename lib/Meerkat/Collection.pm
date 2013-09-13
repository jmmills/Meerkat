use v5.10;
use strict;
use warnings;

package Meerkat::Collection;
# ABSTRACT: Associate class, database and collection
# VERSION

use Moose 2;
use MooseX::AttributeShortcuts;
use Meerkat::Cursor;

use Carp qw/croak/;
use Class::Load qw/load_class/;
use Type::Params qw/compile Invocant/;
use Types::Standard qw/slurpy ArrayRef Defined HashRef Object Optional/;
use Try::Tiny;

use namespace::autoclean;

our @CARP_NOT = qw/Meerkat::Role::Document Try::Tiny/;

#--------------------------------------------------------------------------#
# Public attributes
#--------------------------------------------------------------------------#

=attr meerkat (required)

The Meerkat object that constructed the object.  It holds the MongoDB
collections used to access the database.

=cut

has meerkat => (
    is       => 'ro',
    isa      => 'Meerkat',
    required => 1,
);

=attr class (required)

The class name to associate with documents.

=cut

has class => (
    is       => 'ro',
    isa      => 'Str', # XXX should check that the class does the role
    required => 1,
);

=attr collection_name

The collection name to associate with the class.  Defaults to the
name of the class with "::" replaced with "_".

=cut

has collection_name => (
    is  => 'lazy',
    isa => 'Str',
);

sub _build_collection_name {
    my ($self) = @_;
    ( my $name = $self->class ) =~ s{::}{_}g;
    return $name;
}

#--------------------------------------------------------------------------#
# Constructor
#--------------------------------------------------------------------------#

sub BUILD {
    my ($self) = @_;
    load_class( $self->class );
}

#--------------------------------------------------------------------------#
# Public methods on collection as a whole
#--------------------------------------------------------------------------#

sub count {
    state $check = compile( Object, Optional [HashRef] );
    my ( $self, $query ) = $check->(@_);
    return $self->_mongo_collection->count($query);
}

sub create {
    state $check = compile( Object, slurpy ArrayRef );
    my ( $self, $args ) = $check->(@_);
    my @args = ( ref $args->[0] eq 'HASH' ? %{ $args->[0] } : @$args );
    my $obj = $self->class->new( @args, _collection => $self );
    $self->_save($obj);
    return $obj;
}

sub find_id {
    state $check = compile( Object, Defined );
    my ( $self, $id ) = $check->(@_);
    $id = ref($id) eq 'MongoDB::OID' ? $id : MongoDB::OID->new($id);
    my $data = $self->_mongo_collection->find_one( { _id => $id } );
    return $self->thaw_object($data);
}

sub find_one {
    state $check = compile( Object, HashRef );
    my ( $self, $query ) = $check->(@_);
    my $data = $self->_mongo_collection->find_one($query);
    return $self->thaw_object($data);
}

sub find {
    state $check = compile( Object, HashRef );
    my ( $self, $query ) = $check->(@_);
    my $cursor = $self->_mongo_collection->find($query);
    return Meerkat::Cursor->new( cursor => $cursor, collection => $self );
}

sub ensure_indexes {
    state $check = compile(Object);
    my ($self) = $check->(@_);
    state $aoa_check = compile( slurpy ArrayRef [ArrayRef] );
    my ($aoa) = $aoa_check->( $self->class->_indexes );
    for my $index (@$aoa) {
        my @copy = @$index;
        my $options = ref $copy[0] eq 'HASH' ? shift @copy : {};
        $self->_mongo_collection->ensure_index( \@copy, $options );
    }
    return 1;
}

#--------------------------------------------------------------------------#
# Public methods on individual objects; typically called by object to
# modify itself and synchronize with the database
#--------------------------------------------------------------------------#

sub remove {
    state $check = compile( Object, Object );
    my ( $self, $obj ) = $check->(@_);
    $self->_mongo_collection->remove( { _id => $obj->_id } );
    $obj->_set_removed(1);
    return 1;
}

sub reinsert {
    state $check = compile( Object, Object );
    my ( $self, $obj ) = $check->(@_);
    $self->_save($obj);
    $obj->_set_removed(0);
    return 1;
}

sub sync {
    state $check = compile( Object, Object );
    my ( $self, $obj ) = $check->(@_);
    if ( my $data = $self->_mongo_collection->find_one( { _id => $obj->_id } ) ) {
        $self->_sync( $data => $obj );
        $obj->_set_removed(0);
        return 1;
    }
    else {
        $obj->_set_removed(1);
        return; # false means removed
    }
}

sub update {
    state $check = compile( Object, Object, HashRef );
    my ( $self, $obj, $update ) = $check->(@_);
    my $data = $self->_mongo_collection->find_and_modify(
        {
            query  => { _id => $obj->_id },
            update => $update,
            new    => 1,
        }
    );
    if ($data) {
        $self->_sync( $data => $obj );
        return 1;
    }
    else {
        $obj->_set_removed(1);
        return; # false means removed
    }
}

#--------------------------------------------------------------------------#
# Semi-private methods
#--------------------------------------------------------------------------#

sub thaw_object {
    state $check = compile( Object, HashRef );
    my ( $self, $data ) = $check->(@_);
    $data->{__CLASS__}   = $self->class;
    $data->{_collection} = $self;
    return $self->class->unpack($data);
}

#--------------------------------------------------------------------------#
# Private methods
#--------------------------------------------------------------------------#

sub _mongo_collection {
    state $check = compile(Object);
    my ($self) = $check->(@_);
    return $self->meerkat->get_mongo_collection( $self->collection_name );
}

sub _save {
    state $check = compile( Object, Object );
    my ( $self, $obj ) = $check->(@_);
    my $pack = $obj->pack;
    delete $pack->{$_} for qw/__CLASS__ _collection _removed/;
    return !!$self->_mongo_collection->save($pack);
}

sub _sync {
    state $check = compile( Object, HashRef, Object );
    my ( $self, $data, $tgt ) = $check->(@_);
    my $src = try {
        $self->thaw_object($data);
    }
    catch {
        s/ at \S+ line \d+.*//ms;
        croak "Could not inflate updated document with _id=$data->{_id} because: $_";
    };
    for my $tgt_attr ( $tgt->meta->get_all_attributes ) {
        my $src_attr = $src->meta->find_attribute_by_name( $tgt_attr->name );
        $tgt_attr->set_value( $tgt, $src_attr->get_value($src) );
    }
    return 1;
}

__PACKAGE__->meta->make_immutable;

1;

=for Pod::Coverage method_names_here

=head1 SYNOPSIS

    use Meerkat;

    my $meerkat = Meerkat->new(
        namespace => "MyModel", database_name => "test"
    );

    my $coll = $meerkat->collection("Person"); # MyModel::Person

    # create an object and insert it into the MongoDB collection
    my $obj = $coll->create( name => 'John' );

    # modify an object atomically
    $obj->update_inc ({ likes => 1               }); # increment a counter
    $obj->update_push({ tags => [qw/hot trendy/] }); # push to an array

    # find a single object
    my $copy = $coll->find_one( { name => 'John' } );

    # get a Meerkat::Cursor for multiple objects
    my $cursor = $coll->find( $query_hashref );

=head1 DESCRIPTION

A Meerkat::Collection holds an association between your model class and a
collection in the database.  This class does all the real work of creating,
searching, updating, or deleting from the underlying MongoDB collection.

If you use the Meerkat::Collection object to run a query that could have
multiple results, it returns a Meerkat::Cursor object that wraps the
MongoDB::Cursor and inflates results into objects from your model.

=cut

# vim: ts=4 sts=4 sw=4 et:
