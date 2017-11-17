#!/usr/bin/env perl -CSDL
use strict;
use warnings;

use autodie;

use File::Path qw(make_path);
use File::Temp;
use File::Rsync;
use Mac::iTunes::Library::XML;
use Encode;
use URI::Escape;
use File::Find;
use Data::Dumper;
use Encode qw(decode);

my $library_path = $ARGV[0];
my $target       = $ARGV[1];
my $dry_run      = $ARGV[2];

my %copy_list;
my %lc_copy_list;

my $rsync_path = '/usr/local/bin/rsync';

logger("Reading $library_path");

my $library = Mac::iTunes::Library::XML->parse($library_path);

my $source_root = fix_file_name( $library->musicFolder() );
my %items       = $library->items();

logger("Building rsync list");
my $track_counter = 0;

#start the rsync list with regular tracks
while ( my ( $artist, $artistSongs ) = each %items ) {
    while ( my ( $songName, $artistSongItems ) = each %$artistSongs ) {
        foreach my $item (@$artistSongItems) {

            my $location = $item->location();

            # purchased items that aren't downloaded don't have a location
            if (   $location
                && $location =~ m/^file\:/
                && $location =~ m/\Q$source_root\E/ )
            {

                $location = fix_file_name($location);

                $location =~ s/^\Q$source_root\E/\//;

                $copy_list{$location} = 1;
                $lc_copy_list{ lc($location) } = 1;

                $track_counter++;

                if ( $track_counter % 100 == 0 ) {
                    logger( "$track_counter tracks added, track is",
                        $location );
                }

            }

        }
    }
}

logger("Building current target list");
find(
    sub {
        my $file_path = decode( 'utf8', $File::Find::name );
        my $file = $file_path;
        $file =~ s/^\Q$target\E//;

        return if ( -d $File::Find::name );
        return if ( !$file || $file =~ m/^\/\./ );

        if ( !$lc_copy_list{ lc($file) } ) {
            print "removing $File::Find::name $/";
            unlink $File::Find::name;
        }

    },
    $target
);

my ( $rsync_list_fh, $rsync_list_filename );

if ($dry_run) {
    binmode( STDOUT, ":utf8" );
    $rsync_list_fh       = *STDOUT;
    $rsync_list_filename = 'FILE';
}
else {
    $rsync_list_fh       = File::Temp->new();
    $rsync_list_filename = $rsync_list_fh->filename;
    binmode( $rsync_list_fh, ":utf8" );
}

logger( "Writing $track_counter tracks to rsync list", $rsync_list_filename );

for my $location ( sort keys %copy_list ) {
    print $rsync_list_fh $location . $/;
}
close $rsync_list_fh;

my $rsync = File::Rsync->new(
    {
        'archive'    => 1,
        'delete'     => 1,
        'files-from' => $rsync_list_filename,
        'rsync-path' => $rsync_path,
    }
);

my $rsync_cmd = $rsync->getcmd( { src => $source_root, dest => $target } );

if ($dry_run) {
    logger("Dry run, @$rsync_cmd");
    exit 0;
}

logger( "runnng rsync", @$rsync_cmd );

$rsync->exec(
    {
        src  => $source_root,
        dest => $target
    }
) or warn "rsync failed $!";
logger("writing playlists");

#playlists
my %playlists = $library->playlists();
while ( my ( $playlist_id, $playlist ) = each %playlists ) {

    my $playlist_name = $playlist->name();
    my $m3u_location  = "$target/$playlist_name.m3u8";

    if ( !$playlist->{items} || ref $playlist->{items} ne 'ARRAY' ) {
        next;
    }

    open my $fh, '>', $m3u_location;
    binmode $fh, ':utf8';

    logger( "writing playlist", $m3u_location );

    print $fh "#EXTM3U$/";

    for my $item ( $playlist->items() ) {
        my $location = $item->location();

        if (   $location
            && $location =~ m/^file\:/
            && $location =~ m/\Q$source_root\E/ )
        {
            $location = fix_file_name( $item->location );

            $location =~ s/^\Q$source_root\E//;

            my ( $timeMillis, $artist, $track ) = (
                $item->totalTime,
                $item->artist // $item->albumArtist // '',
                $item->name // ''
            );
            my $timeSeconds = int( ( $timeMillis / 1000 ) + 0.5 );

            print $fh "#EXTINF:$timeSeconds,$artist - $track$/";

            print $fh $location . $/;
        }
    }

    close $fh;
}

logger("Done");

sub fix_file_name {
    my ($location) = @_;
    $location =~ s/^file:\/\///;
    $location = Encode::decode( 'utf8', uri_unescape($location) );
    return $location;
}

sub logger {
    print STDERR join( "\t", @_ ) . $/;
}
