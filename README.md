# iTunesExporter
Export an iTunes library to a directory (e.g. SD card)


## Requirements

 * perl (tested with v5.20.2)
 * cpan modules:
   * autodie
   * File::Rsync
   * Mac::iTunes::Library::XML
   * URI::Encode
 * an iTunes library xml file
 * rsync
 * a unix like environment (tested on OSX)
 
## Usage

`iTunesExporter.pl itunesLibrary.xml <target dir>`

e.g.

`iTunesExporter.pl /Users/Dave/Music/iTunes/iTunes\ Music\ Library.xml /Volumes/Music`

This will copy all readable items in your iTunes library to the target location, preserving the existing folder structure. It will also convert your playlists into m3u playlists, in the target directory.

Files in the target directory that aren't in the library will be deleted.

I developed this for my own use with an AGPTek Rocker mp3 player and offer it as is. I've tested it with about 7000 files on a 128Gb micro SD card. Repeated runs of the script should be quicker, as it doesn't copy files already present in the target directory.

