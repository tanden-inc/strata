// Module manifest for Strata (https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html)
name = "tanden-inc/strata"

version = "0.1.0"

import {
  "moonbitlang/async@0.21.2",
}

readme = "README.md"

repository = "https://github.com/tanden-inc/strata"

license = "Apache-2.0"

keywords = [ "event-sourcing", "cqrs", "dcb", "decider", "ddd" ]

description = "Event sourcing for MoonBit: deciders, advice, selections, dynamic consistency boundaries, projections and reactors"

preferred_target = "native"

source = "."

warnings = "+missing_doc"
