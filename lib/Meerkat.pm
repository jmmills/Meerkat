use v5.10;
use strict;
use warnings;

package Meerkat;
# ABSTRACT: Manage MongoDB documents as Moose objects
# VERSION

# Dependencies
use Moose 2;
use MooseX::AttributeShortcuts;

use Meerkat::Collection;
use Module::Runtime qw/require_module compose_module_name/;
use MongoDB;
use Try::Tiny;
use Type::Params qw/compile/;
use Types::Standard qw/:types/;

use namespace::autoclean;

with 'MooseX::Role::Logger', 'MooseX::Role::MongoDB' => { -version => 0.006 };

=attr model_namespace (required)

A perl module namespace that will be prepended to class names requested
via the L</collection> method.  If C<model_namespace> is "My::Model", then
C<< $meerkat->collection("Baz") >> will load and associate the
C<My::Model::Baz> class in the returned collection object.

=cut

has model_namespace => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

=attr database_name (required)

A MongoDB database name used to store all collections generated via the Meerkat
object and its collection factories.  Unless a C<db_name> is provided in the
C<client_options> attribute, this database will be the default for
authentication.

=cut

has database_name => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

=attr client_options

A hash reference of L<MongoDB::MongoClient> options that will be passed to its
C<connect> method.

Note: The C<dt_type> will be forced to C<undef> so that the MongoDB client will
provide time values as epoch seconds.  See the L<Meerkat::Cookbook> for more on
dealing with dates and times.

=cut

has client_options => (
    is      => 'ro',
    isa     => 'HashRef', # hashlike?
    default => sub { {} },
);

=attr collection_namespace

A perl module namespace that will be be used to search for custom collection
classes.  The C<collection_namespace> will be prepended to class names
requested via the L</collection> method.  If C<collection_namespace> is
"My::Collection", then C<< $meerkat->collection("Baz") >> will load and use
C<My::Collection::Baz> for constructing a collection object.  If
C<collection_namespace> is not provided or if no class is found under the
namespace (or if it fails to load), then collection objects will be constructed
using L<Meerkat::Collection>.

=cut

has collection_namespace => (
    is  => 'ro',
    isa => 'Str',
);

=attr default_collection_class

Defaults to L<Meerkat::Collection>. Set this to a class name that extends
L<Meercat::Collection> to set a default collection class.

=cut

has default_collection_class => (
    is      => 'ro',
    isa     => 'Str',
    default => 'Meerkat::Collection'
);

sub BUILD {
    my ($self) = @_;

    # We force MongoDB to convert its internal datetimes to epoch values so we
    # can proxy them with Meerkat::DateTime objects; storage of DateTime or
    # DateTime::Tiny are automatically converted regardless of this setting.
    $self->client_options->{dt_type} = undef;
}

# configure MooseX::Role::MongodB
sub _build__mongo_client_options   { $_[0]->client_options }
sub _build__mongo_default_database { $_[0]->database_name }

#--------------------------------------------------------------------------#
# Methods
#--------------------------------------------------------------------------#

=method new

    my $meerkat = Meerkat->new(
        model_namespace => "My::Model",
        database_name   => "test",
        client_options  => {
            host => "mongodb://example.net:27017",
            username => "willywonka",
            password => "ilovechocolate",
        },
    );

Generates and returns a new Meerkat object.  The C<model_namespace> and
C<database_name> attributes are required.

=method collection

    my $person = $meerkat->collection("Person"); # My::Model::Person

Returns a L<Meerkat::Collection> factory object or possibly a subclass if a
C<collection_namespace> attribute has been provided. A single parameter is
required and is used as the suffix of a class name provided to the
Meerkat::Collection C<class> attribute.

=cut

sub _load_default_collection_class {
    my $self = shift;
    
    my $class = $self->default_collection_class;
    
    return $class if $class eq 'Meerkat::Collection';
    
    require_module($class);
    
    return $class;
}

sub collection {
    state $check = compile( Object, Str );
    my ( $self, $suffix ) = $check->(@_);
    my $model = compose_module_name( $self->model_namespace, $suffix );
    my $class;
    if ( my $prefix = $self->collection_namespace ) {
        $class = compose_module_name( $prefix, $suffix );
        try { require_module($class) } catch { $class = $self->_load_default_collection_class };
    }
    else {
        $class = $self->_load_default_collection_class;
    }
    $DB::single=1;
    return $class->new( class => $model, meerkat => $self );
}

=method mongo_collection

    my $coll = $meerkat->mongo_collection("My_Model_Person");

Returns a raw L<MongoDB::Collection> object from the associated database.
This is used internally by L<Meerkat::Collection> and is not intended for
general use.

=cut

# alias _mongo_collection provided by MooseX::Role::MongoDB
*mongo_collection = *_mongo_collection;

__PACKAGE__->meta->make_immutable;

1;

=for Pod::Coverage BUILD

=head1 SYNOPSIS

    use Meerkat;

    my $meerkat = Meerkat->new(
        model_namespace => "My::Model",
        database_name   => "test",
        client_options  => {
            host => "mongodb://example.net:27017",
            username => "willywonka",
            password => "ilovechocolate",
        },
    );

    my $person = $meerkat->collection("Person"); # My::Model::Person

    # create an object and insert it into the MongoDB collection
    my $obj = $person->create( name => 'John' );

    # modify an object atomically
    $obj->update_inc ( likes => 1               ); # increment a counter
    $obj->update_push( tags => [qw/hot trendy/] ); # push to an array

    # find a single object
    my $copy = $person->find_one( { name => 'John' } );

    # get a Meerkat::Cursor for multiple objects
    my $cursor = $person->find( { tags => 'hot' } );

=head1 DESCRIPTION

Meerkat lets you manage MongoDB documents as Moose objects.  Your objects
represent projections of the document state maintained in the database.

When you create an object, a corresponding document is inserted into the
database.  This lets you use familiar Moose attribute builders and validation
to construct your documents.

Because state rests in the database, you don't modify your object with
accessors.  Instead, you issue MongoDB update directives that change the state
of the document atomically in the database and synchronize the object state
with the result.

Meerkat is not an object-relational mapper.  It does not offer or manage relations
or support embedded objects.

Meerkat is fork-safe.  It maintains a cache of MongoDB::Collection objects that
gets cleared when a fork occurs.  Meerkat will transparently reconnect from
child processes.

=head1 USAGE

Meerkat divides functional responsibilities across six classes:

=for :list
* L<Meerkat> — associates a Perl namespace to a MongoDB connection and database
* L<Meerkat::Collection> — associates a Perl class within a namespace to a MongoDB collection
* L<Meerkat::Role::Document> — enhances a Moose object with Meerkat methods and metadata
* L<Meerkat::Cursor> — proxies a result cursor and inflates documents into objects
* L<Meerkat::DateTime> — proxies an epoch value with lazy DateTime inflation
* L<Meerkat::Types> — provides type definition and coercion for Meerkat::DateTime

You define your documents as Moose classes that consume
Meerkat::Role::Document.  This gives them several support methods to update,
synchronize or remove documents from the database.

In order to create objects from your model or retrieve them from the database,
you must first create a Meerkat object that manages your connection to the
MongoDB database.  This is where you specify your database host, authentication
options and so on.

You then get a Meerkat::Collection object from the Meerkat object, which holds
an association between the model class and a collection in the database.  This
class does all the real work of creating, searching, updating, or deleting from
the underlying MongoDB collection.

If you use the Meerkat::Collection object to run a query that could have
multiple results, it returns a Meerkat::Cursor object that wraps the
MongoDB::Cursor and inflates results into objects from your model.

Meerkat::DateTime lazily inflates floating point epoch seconds into L<DateTime>
objects.  It's conceptually similar to L<DateTime::Tiny>, but based on the
epoch seconds returned by the MongoDB client for its internal date value
representation.

See L<Meerkat::Tutorial> and L<Meerkat::Cookbook> for more.

=head1 EXCEPTION HANDLING

Unless otherwise specified, all methods throw exceptions on error either directly
or by not catching errors thrown by MongoDB classes.

=head1 WARNINGS AND CAVEATS

Your objects are subject to the same limitations as any MongoDB document.

Most significantly, because MongoDB uses the dot character as a field separator
in queries (e.g. C<foo.bar>), you may not have the dot character as the key of any
hash in your document.

    # this will fail
    $person->create( emails => { "dagolden@example.com" => "primary" } );

Be particularly careful with email addresses and URLs.

=head1 RATIONALE

Working with raw MongoDB documents as pure data structures is a bit painful and
annoying.  There are some existing libraries that attempt to make life easier,
but I found them deficient in one way or another.

I tried L<Mongoose> first.  I had problems when trying to work with multiple
databases and doing any sort of authentication and it doesn't seem very
actively maintained.  L<MongoDBX::Class> (discussed next) has some L<additional
Mongoose critiques|MongoDBx::Class/COMPARISON WITH OTHER MongoDB ORMs>.
Mongoose is about 1000 lines of code split across fourteen modules.

Next I looked at L<MongoDBx::Class>.  In many ways, it works much more like the
basic L<MongoDB> classes.  What stopped me cold was that it requires inserts to be
done with a raw data structure.  That means no defaults, validation, lazy
building and other stuff that I like about Moose.  It does offer some support
making updates easier, and I've adapted that approach for Meerkat.
MongoDBx::Class is about 800 lines of code split across fifteen modules.

Both offer a relational model.  While a noble goal, I'm suspicious of applying
relational data models to a document-oriented database like MongoDB that
doesn't have transactions.  MongoDB offers atomic I<document> updates, so I
decided to focus Meerkat on that alone.

Mongoose and MongoDBx also support defining embedded documents.  I haven't
decided if that's necessary — and it adds quite a bit of complexity — so I
haven't implemented it in Meerkat.

There are other MongoDB-based modules that I found and dismissed:

=for :list
* L<KiokuDB::Backend::MongoDB>, but see the Mongoose L<critique of it|Mongoose::Intro/MOTIVATION>
* L<MongoDB::Simple>, which is too simple to do what I want
* L<MongoDBx::Tiny>, which hurts my eyes
* L<MongoDBI>, "scheduled for a rewrite in the coming months" for the last year

Conceptually, Meerkat is a bit similar to Mongoose, but less ambitious.  (A
meerkat is a smaller member of the mongoose family, after all.)  It adopts
some of the features I liked from MongoDBx::Class.

Meerkat focuses on:

=for :list
* Multiple database support
* Easy configuration of database connections
* Fork safety
* Simplicity and (to the extent possible) Moosey-ness
* A document-centric data model

Because it is less ambitious, Meerkat is smaller and less complex, currently
about 480 lines of code split across six modules.

=head1 SEE ALSO

=head2 Meerkat documentation

=for :list
* L<Meerkat::Tutorial>
* L<Meerkat::Cookbook>

=head2 Other MongoDB resources

=for :list
* L<MongoDB::MongoClient>
* L<MongoDBx::Class>
* L<Mongoose>

=cut

# vim: ts=4 sts=4 sw=4 et:
