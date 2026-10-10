# Prior knowledge: bootc/OCI/RPM, new to BuildStream

The user maintains finpilot (a bootc/OCI/RPM image template) and knows that
world deeply — Containerfiles, OCI layers, RPM/COPR, ostree, bootc. BuildStream
is new territory: the declarative graph, content-addressed cache keys, and
junctions are the concepts to teach, not the packaging.

Implication: start from the mental shift (recipe → graph) and map new terms onto
the Containerfile world the user already holds. Don't spend time on what an
image or a registry is.
