# SPFKFileSystem

[![Version](https://img.shields.io/github/v/tag/ryanfrancesconi/spfk-filesystem)](https://github.com/ryanfrancesconi/spfk-filesystem/tags)
[![Swift](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fryanfrancesconi%2Fspfk-filesystem%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/ryanfrancesconi/spfk-filesystem)
[![Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fryanfrancesconi%2Fspfk-filesystem%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/ryanfrancesconi/spfk-filesystem)

File system utilities for working with files in place: enumerating and observing directories,
Finder tags and extended attributes, and Finder-style file commands.

## Features

- Enumerate and observe directory trees
- Observe volumes mounting and unmounting
- Tell a content change from an attribute-only change (`FileModificationState`)
- Read and write Finder tags and extended attributes
- Detect a file whose content does not match its extension (`ContainerSignature`)
- Report why a file refuses a write (`FileLockState`)
- Rename, duplicate, move to trash and restore (`FileCommands`)
- Finder tags, volume and modification observation, and the file commands are macOS only

## Notes

- Writing an extended attribute, including a Finder tag, changes a file's attribute modification
  date and not its content modification date. Compare the content date to decide whether to re-read
  a file.

## About

Spongefork is the personal software projects of musician and developer [Ryan Francesconi](https://spongefork.com). Dedicated to creative sound manipulation, his first application, Spongefork, was released in 1999 for macOS 8. From 2026, Spongefork returns as his software container for more musical experimentation. In addition to [software releases](https://spongefork.com/shadowtag/), open source components can be found on his [GitHub page](https://github.com/ryanfrancesconi).
