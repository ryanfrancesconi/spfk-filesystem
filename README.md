# SPFKFileSystem

[![Version](https://img.shields.io/github/v/tag/ryanfrancesconi/spfk-filesystem)](https://github.com/ryanfrancesconi/spfk-filesystem/tags)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fryanfrancesconi%2Fspfk-filesystem%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/ryanfrancesconi/spfk-filesystem)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fryanfrancesconi%2Fspfk-filesystem%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/ryanfrancesconi/spfk-filesystem)

The file-system layer an app embeds to manage files the user keeps in place: finding them, watching
them, and acting on them the way Finder would.

It enumerates and observes directory trees, notices volumes coming and going, tells whether a file
changed in content or only in attributes, reads and writes Finder tags and extended attributes,
recognizes when a file's content contradicts its extension, explains why a file refuses a write,
and runs Finder-style commands such as rename, duplicate and move to trash. Enumeration, directory
observation and content sniffing work on iOS too; Finder tags, volume and modification observation,
and the file commands are macOS-only.

Nothing here knows what a file contains or what a library is: format parsing belongs to the media
packages, and library state to spfk-playlist-data.

## Attributes versus content

Writing an extended attribute, which is where Finder tags live, moves a file's attribute
modification date and leaves its content date alone. Anything deciding whether to re-read a file
should compare the content date, or a Finder tag change costs a full re-parse.

## About

Spongefork is the personal software projects of musician and developer [Ryan Francesconi](https://spongefork.com). Dedicated to creative sound manipulation, his first application, Spongefork, was released in 1999 for macOS 8. From 2026, Spongefork returns as his software container for more musical experimentation. In addition to [software releases](https://spongefork.com/shadowtag/), open source components can be found on his [GitHub page](https://github.com/ryanfrancesconi).
