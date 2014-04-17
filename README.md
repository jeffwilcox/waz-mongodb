waz-mongodb
===========

An unofficial set of Bash scripts to build out a simple MongoDB replica set, designed for Microsoft Azure Linux compute VMs.

Created for [this blog post by Jeff Wilcox](http://www.jeff.wilcox.name/2013/09/mongodb-azure-linux/).

## Supported versions

This script currently is designed to deploy MongoDB 2.6 replica sets.

### Upgrading from 2.4 to 2.6

When this script was originally released, it targeted 2.4. 2.6 is a major upgrade; to upgrade, build out a set of new VMs to replace the replica set (lowest impact), or upgrade individuals starting with the secondaries. [Upgrade guidance is available from MongoDB](docs.mongodb.org/manual/release-notes/2.6-upgrade/).

### YAML Configuration
The configuration file for 2.6 is at `/etc/mongod.conf`, but it is now ideally a YAML-formatted file going forward. [Configuration settings documentation here](http://docs.mongodb.org/manual/reference/configuration-options/). The old format will be supported by MongoDB for some time, but this script now writes the newer YAML format.
