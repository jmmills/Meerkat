use strict;
use warnings;
use Test::Roo;
use Test::FailWarnings;
use Test::Deep '!blessed';
use Test::Fatal;
use Test::Requires qw/MongoDB::MongoClient/;

my $conn = eval { MongoDB::MongoClient->new; };
plan skip_all => "No MongoDB on localhost" unless $conn;

use lib 't/lib';

with 'TestFixtures';

test 'bad sync' => sub {
    my $self = shift;
    my $obj  = $self->create_person;
    my $copy = $self->person->find_id( $obj->_id );

    # intentionally create a bad document
    $self->person->_mongo_collection->update( { _id => $obj->_id }, { name => [] } );

    like(
        exception { $obj->sync },
        qr/Could not inflate updated document/,
        "syncing a bad document threw an exception"
    );
    cmp_deeply( $obj, $copy, "object is unchanged" );
};

run_me;
done_testing;
# COPYRIGHT
# vim: ts=4 sts=4 sw=4 et: