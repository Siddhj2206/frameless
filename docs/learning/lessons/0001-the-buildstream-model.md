# Lesson 1: The BuildStream model

**Mission link:** you maintain frameless, so you need to reason about the build
graph, not just run it.

## The one idea

The repo you inherited is a Containerfile: an imperative list of `RUN` layers.
BuildStream is the opposite — you **declare a graph** and the tool decides what
to run. Each node is cached independently, so changing one component rebuilds
exactly its consumers.

That single shift explains almost everything else.

## Four nouns

- **element** — a node, a `.bst` file, keyed by a plugin `kind`
- **source** — a pinned input (`git`, `tar`, `docker`, `local`)
- **junction** — a window into another BuildStream project
- **artifact** — the cached output

A junction is how frameless will pull in all of freedesktop-sdk without copying
it. The dependency graph crosses the junction with element paths.

## Why the cache matters

Every element's **cache key** is derived from its config, sources, and
dependencies. A shared artifact cache means a cold CI job can pull most of the
graph instead of rebuilding it. This is the whole reason the Bluefin repos use
the public caches in their `project.conf`.

## Try it

`bst` isn't installed here; run it in the pinned freedesktop-sdk container
(command and gotchas: `docs/research/05-local-bst-runner.md`). Build the
upstream "hello world":

1. Make a project with a `project.conf` and one `elements/hello.bst` of
   `kind: import` (see the [first-project tutorial](https://docs.buildstream.build/master/tutorial/first-project.html)).
2. Run `bst build hello.bst` through the container wrapper.
3. Run `bst show hello.bst` — the state should read `cached`.
4. Run `bst artifact checkout --directory here hello.bst` and look at the file.

You just declared a graph, built it, and pulled the result back out of the cache.

## Check yourself

1. What determines whether an element rebuilds?
2. What is a junction, and why will frameless need one for freedesktop-sdk?
3. In `stack` → `compose` → `script(build-oci)`, which step produces the OCI image?

## Primary source

The [BuildStream getting-started tutorial](https://docs.buildstream.build/master/using_tutorial.html).

Ask me anything this doesn't land — I'm your teacher for this, not just the
agent doing the work.
