# Shared scenarios

`task-transitions.json` lists task status transitions as data: a starting state, an event and
the expected result. Every implementation that changes task status (the Go Lambdas and the
Python worker) runs the same file in its tests, so they cannot drift apart.
