#!/bin/sh
# The build number, Android's version code and iOS's build: the commit count, so that each build
# goes up. Plus the 11 commits of the segue repository (the protocol and the hub, where the app
# lived until 2026-10-05) that didn't touch the app, so that the count goes on from where it was.
echo $(($(git -C "$(dirname "$0")" rev-list --count HEAD) + 11))
