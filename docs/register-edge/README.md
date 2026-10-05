# Plain customer-facing checkout panel

The checkout previously reused the storage cabinet's doors and handles on its customer-facing side. It now draws the same cabinet box with a plain front panel. This also removes the drawer-like seam that could show through rear views. Ordinary storage cabinets retain their doors and handles.

The terminal, screen, keys, payment pad, receipt, status light, footprint and all staff/customer coordinates keep their existing orientation. This adds no drawer mechanics, payment behavior or save changes.

Run `python3 tests/run_integration_candidate.py --output /absolute/new/evidence --only test_register_edge`. The 80 focused assertions cover all four turns and idle, paying and recently paid states. Primitive tracing confirms unrelated drawing commands remain unchanged. Matched native views were also inspected with generated scenes and suppressed saves.

`qa/capture_register_edge.gd` provides the reproducible native fixture. Use an isolated HOME/XDG profile and `--visual-qa --fresh-review --skip-intro`, with `OUTPUT` and `PHASE` set. Review images are kept outside the source repository.

This completes the reported customer-facing drawer defect. Separate final-image user acceptance is not claimed. No asset or license changes are introduced.
