# plugins

A local BuildStream plugin, registered in `project.conf` under
`origin: local, path: plugins`.

`chunkah-ownership.{py,yaml}` defines a `kind: chunkah-ownership` element. It
generates the ownership basis for a compose layer — who owns which path —
without replaying the layer. `elements/oci/chunkah/frameless.bst` uses it, and
`just chunkify` turns the result into content-chunked layers so updates are
smaller.

Everything else in the graph comes from junctioned plugin packages, which live at
`../elements/plugins/` — a different directory with a confusingly similar name.
