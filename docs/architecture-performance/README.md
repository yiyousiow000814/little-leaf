# Architecture and performance

This is a documentation-only proposal. It does not alter gameplay, claim the existing implementation is compliant, or certify any platform at 60 FPS.

- [Architecture contract](architecture-contract.md): responsibilities, extension rules, complexity limits, and the 60 FPS gate with 15% unused frame budget.
- [Proposed workflow](target-workflow.mmd): intended dependency and ownership boundaries, not an implemented revision.
- [Current function atlas](current-function-atlas.mmd): all 2,209 named GDScript functions in 136 files and 3,840 statically resolved call relationships, at [d81afcd5](https://github.com/yiyousiow000814/little-leaf/tree/d81afcd5b760eb4cc70eb941b4c28795f8c04df6). Dashed edges are cross-file calls. Dynamic signal/engine dispatch is not inferred.
- [Performance workload ledger](performance-workload-ledger.xlsx): the complete workbook derived from v68. Private evidence locations are represented by stable evidence labels. Original measurements remain attributed to their own test source and conditions.
- [Atlas generator](generate-function-atlas.py): conservative lexical extraction, using only the Python standard library. Run from the repository root:
  ```sh
  python3 docs/architecture-performance/generate-function-atlas.py . /tmp/little-leaf-atlas --revision "$(git rev-parse HEAD)"
  ```
  The extractor also generates function and call-site indexes and an unresolved-call report. The complete atlas is Mermaid source; GitHub's inline renderer can limit large diagrams. Start from a function or module for readable review rather than relying on one giant SVG.

For each game change, update the atlas and workbook together, point them to the same reviewed source revision, and keep source-derived operation counts separate from measured timings and presentation results.
