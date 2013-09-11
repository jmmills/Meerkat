# COPYRIGHTuse strict;
use warnings;
use Test::Roo;
use Test::Deep '!blessed';
use Test::FailWarnings;
use Test::Fatal;
use Test::Requires qw/MongoDB::MongoClient/;

my $conn = eval { MongoDB::MongoClient->new; };
plan skip_all => "No MongoDB on localhost" unless $conn;

use lib 't/lib';

with 'TestFixtures';

test 'update_set' => sub {
    my $self = shift;
    my $obj  = $self->create_person;
    $obj->update_set( name => "Larry Wall" );
    is( $obj->name, "Larry Wall", "attribute set in object" );
    my $got = $self->person->find_id( $obj->_id );
    is( $got->name, "Larry Wall", "attribute set in DB" );
};

test 'update_inc' => sub {
    my $self = shift;
    my $obj  = $self->create_person;
    $obj->update_inc( likes => 1 );
    is( $obj->likes, 1, "attribute incremented in object" );
    my $got = $self->person->find_id( $obj->_id );
    is( $got->likes, 1, "attribute incremented in DB" );
};

test 'update_push' => sub {
    my $self     = shift;
    my $obj      = $self->create_person;
    my @expected = qw/cool trendy/;

    # push list
    $obj->update_push( tags => @expected );
    cmp_deeply( $obj->tags, bag(@expected), "pushed values in object" );
    my $got = $self->person->find_id( $obj->_id );
    cmp_deeply( $got->tags, bag(@expected), "pushed values in DB" );

    # push hashref
    my $hashref = { key => 'value' };
    $obj->update_push( tags => $hashref );
    cmp_deeply( $obj->tags, bag( @expected, $hashref ), "pushed hashref in object" );
    $got = $self->person->find_id( $obj->_id );
    cmp_deeply( $got->tags, bag( @expected, $hashref ), "pushed hashref in DB" );

};

test 'update_add' => sub {
    my $self     = shift;
    my $obj      = $self->create_person;
    my @expected = qw/cool trendy/;

    # push list twice
    $obj->update_add( tags => @expected );
    $obj->update_add( tags => @expected );
    cmp_deeply( $obj->tags, bag(@expected), "values only show up once in object" );
    my $got = $self->person->find_id( $obj->_id );
    cmp_deeply( $got->tags, bag(@expected), "values only show up once in DB" );

    # push hashref twice
    my $hashref = { key => 'value' };
    $obj->update_add( tags => $hashref );
    $obj->update_add( tags => $hashref );
    cmp_deeply(
        $obj->tags,
        bag( @expected, $hashref ),
        "hashref only shows up once in object"
    );
    $got = $self->person->find_id( $obj->_id );
    cmp_deeply(
        $got->tags,
        bag( @expected, $hashref ),
        "hashref only shows up once in DB"
    );

};

run_me;
done_testing;
# COPYRIGHT
# vim: ts=4 sts=4 sw=4 et:
# vim: ts=4 sts=4 sw=4 et: