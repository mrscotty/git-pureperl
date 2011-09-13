# t/sha.t
#
# Confirm that the SHA1 is getting created correctly.
#
# Test set 1 - create two blob objects and one tree object and
# confirm the resulting SHA1 values
#
# The git binary can be used to get the reference values as follows
# (the dollar '$' is the command shell prompt):
#
#   $ mkdir sha1-test.git
#   $ cd sha1-test.git
#   $ git init
#   Initialized empty Git repository in /home/scott/sha1-test.git/.git/
#   $ echo -n '123' | git hash-object -w --stdin
#   d800886d9c86731ae5c4a62b0b77c437015e00d2
#   $ echo -n '789' | git hash-object -w --stdin
#   be2fb0a390d694f75a1e5957254c29d7957fa3a2
#   $ git update-index --add --cacheinfo 100644 \
#     d800886d9c86731ae5c4a62b0b77c437015e00d2 host1
#   $ git update-index --add --cacheinfo 100644 \
#     be2fb0a390d694f75a1e5957254c29d7957fa3a2 host2
#   $ git write-tree
#   c2b1cf11f2abf788bfef75bbdf0263c84c3eb058
#
#
#

BEGIN {
    eval 'require Config::Merge;';
    our $req_cm_err = $@;
}

use Test::More tests => 2;
use DateTime;
use Path::Class;
use Git::PurePerl;
use Carp qw(confess);

our $git;

my $gitdb = 't/sha.git';

my $file1_name    = 'host1';
my $file1_content = '123';
my $file1_sha     = 'd800886d9c86731ae5c4a62b0b77c437015e00d2';
my $file2_name    = 'host2';
my $file2_content = '789';
my $file2_sha     = 'be2fb0a390d694f75a1e5957254c29d7957fa3a2';
my $tree1_sha     = 'c2b1cf11f2abf788bfef75bbdf0263c84c3eb058';

my $root_tree_sha1 = '1f966cb8b26bd044c34077b8931a0f74d849be8c';
my $commit_1_sha1 = 'd1bbe8a02bdfd09af6c988b986089ba3e32756b5';

my @dir_entries = ();

# This helper routine converts the Config::Merge data structure
# into a simple hash tree
sub cm2hash {
    my $cm   = shift;
    my $tree = {};
    if ( ref($cm) eq 'HASH' ) {
        my $ret = {};
        foreach my $key ( keys %{$cm} ) {
            $ret->{$key} = cm2hash( $cm->{$key} );
        }
        return $ret;
    }
    elsif ( ref($cm) eq 'ARRAY' ) {
        my $ret = {};
        my $i   = 0;
        foreach my $entry ( @{$cm} ) {
            $ret->{ $i++ } = cm2hash($entry);
        }
        return $ret;
    }
    else {
        return $cm;
    }
}

sub hash2tree {
    my $hash = shift;

    if ( ref($hash) ne 'HASH' ) {
        confess "ERR: hash2tree() - arg not hash ref [$hash]";
    }
    if ( $debug ) {
        warn "Entered hash2tree( $hash ): ", join(', ', %{ $hash }), "\n";
    }

    my @dir_entries = ();

    foreach my $key ( keys %{$hash} ) {
        if ($debug) {
                warn "# hash2tree() processing $key -> ", $hash->{$key}, "\n";
        }
        if ( ref( $hash->{$key} ) eq 'HASH' ) {
            if ( $debug ) {
                warn "# hash2tree() adding subtree for $key\n";
            }
            my $subtree = hash2tree( $hash->{$key} );
            my $de      = Git::PurePerl::NewDirectoryEntry->new(
                mode     => '40000',
                filename => $key,
                sha1     => $subtree->sha1,
            );
            push @dir_entries, $de;
        }
        else {
            my $obj =
              Git::PurePerl::NewObject::Blob->new( content => $hash->{$key} );
            $git->put_object($obj);
            my $de = Git::PurePerl::NewDirectoryEntry->new(
                mode     => '100644',
                filename => $key,
                sha1     => $obj->sha1,
            );
            push @dir_entries, $de;
        }
    }
    my $tree = Git::PurePerl::NewObject::Tree->new(
        directory_entries => [
            sort {
                  $a->filename cmp $b->filename
              } @dir_entries
        ]
    );

    if ($debug) {
        my $content = $tree->content;
        $content =~ s/(.)/sprintf("%x",ord($1))/eg;
        warn "# Added tree with dir entries: ",
          join( ', ', map { $_->filename } @dir_entries ), "\n";
        warn "#     content: ", $content, "\n";
        warn "#     size: ", $tree->size, "\n";
        warn "#     kind: ", $tree->kind, "\n";
        warn "#     sha1: ", $tree->sha1, "\n";

    }

    $git->put_object($tree);

    return $tree;
}


SKIP: {
    skip "Config::Merge not installed", 2 if $req_cm_err;

    # (re)-initialize Git test repository

    dir($gitdb)->rmtree;
    dir($gitdb)->mkpath;
    $git = Git::PurePerl->init( gitdir => $gitdb );

    # Import configuration data using Config::Merge

    my $cm = Config::Merge->new('t/sha.d');
    my $cmref = $cm->();

    # Massage the data from Config::Merge, create the Git::PurePerl
    # objects and commit the tree
    
    my $hash = cm2hash($cmref);
    my $tree = hash2tree($hash);

    my $actor = Git::PurePerl::Actor->new(
        name => 'Test User',
        email => 'test@example.com',
    );
    my $time = DateTime->from_epoch( epoch => 1240341682 );

    my @commit_attrs = (
        tree    => $tree->sha1,
        author => $actor,
        authored_time => $time,
        committer => $actor,
        committed_time => $time,
        comment => 'Import config for sha.t'
    );
    my $commit = Git::PurePerl::NewObject::Commit->new(@commit_attrs);
    $git->put_object($commit);

    is($tree->sha1, $root_tree_sha1, 'Check sha1 of root tree obj');

    my $obj = $git->get_object($root_tree_sha1);
    ok($obj->sha1, 'Fetch root tree obj from git');

}
