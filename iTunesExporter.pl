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

use Data::Dumper;

my $library_path = $ARGV[0];
my $target       = $ARGV[1];

my %copy_list;

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

                $track_counter++;

                if ( $track_counter % 100 == 0 ) {
                    logger( "$track_counter tracks added, track is",
                        $location );
                }

            }

        }
    }
}

my $rsync_list_fh       = File::Temp->new();
my $rsync_list_filename = $rsync_list_fh->filename;

binmode( $rsync_list_fh, ":utf8" );

logger( "Writing $track_counter tracks to rsync list", $rsync_list_filename );

for my $location ( sort keys %copy_list ) {
    print $rsync_list_fh $location . $/;
}
close $rsync_list_fh;

my $rsync = File::Rsync->new(
    {
        'archive'       => 1,
        'delete-before' => 1,
        'files-from'    => $rsync_list_filename
    }
);

my $rsync_cmd = $rsync->getcmd( { src => $source_root, dest => $target } );

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

    for my $item ( $playlist->items() ) {
        my $location = $item->location();

        if (   $location
            && $location =~ m/^file\:/
            && $location =~ m/\Q$source_root\E/ )
        {
            $location = fix_file_name( $item->location );

            $location =~ s/^\Q$source_root\E//;
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
