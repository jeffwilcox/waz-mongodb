waz-mongodb
===========

An unofficial set of Bash scripts to build out a simple MongoDB replica set, designed for Windows Azure Linux compute VMs.

## Supported versions

This script currently is designed to deploy MongoDB 2.6 replica sets.

### Upgrading from 2.4 to 2.6

When this script was originally released, it targeted 2.4. 2.6 is a major upgrade; to upgrade, build out a set of new VMs to replace the replica set (lowest impact), or upgrade individuals starting with the secondaries. [Upgrade guidance is available from MongoDB](docs.mongodb.org/manual/release-notes/2.6-upgrade/).