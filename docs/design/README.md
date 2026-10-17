# Design

Use the [canonical roadmap](../roadmap.md) for current scope, ownership and status. These contracts specify behavior and constraints; approval of a document does not establish implemented code or accepted game pixels.

- [Owned Storage in Decorate](owned-storage.md)
- [Character authoring and accessories](cute-staff-accessories-011.md)
- [Eight-direction routing design](rc-inspired-routing-011.md), with [verification cases](../testing/rc-inspired-routing-011-qa.md)
- [Starter-wall geometry and migration](starter-wall-grid-segments.md), [implementation review](starter-wall-implementation-review.md) and [source-bound review data](starter-wall-design-review.json)
- [Scoped product acceptance](../testing/README.md) maps the intended outcomes to verification gates.

The [historical 0.1.11 approval record](history/design-011-approved-plan.md) preserves the agreed directions at its stated date. Follow the roadmap for current decisions.

## Feature Design Quality Gate

Apply this gate before implementing a player-facing change. Record the result in
its existing design note or PR description; use the [eight canonical framework
homes](../README.md#game-production-framework), not another plan or checklist file.
Scale the review to the actual change. A small fix does not need every domain's
runtime test, a new art sample or a new authoring workflow.

- **Purpose and authority:** state the player problem, intended outcome and the
  recorded requirement or approved direction. Label historical reference era,
  confidence and deliberate differences. A reference or proposal is not permission
  to simplify strategy, alter economics, create customers or change save policy.
- **Reuse and ownership:** identify existing components, semantic UI styles,
  editable assets and authoritative state owners before adding a parallel path.
  Explain a necessary new boundary. Preserve identity, custody, clocks, contacts,
  source/licensing history and active owners' work across interacting systems.
- **Relevant pillars:** identify which of Art, Technical Art, Audio, Living World,
  Game Feel/Animation, UI/UX and Gameplay Reference are affected, and link their
  applicable rules. State why the others are unaffected. Include normal, repeated,
  interrupted and recovery transitions only where the change can alter them.
- **Cost and evidence:** identify per-frame work, retained resources, invalidation
  and release ownership using existing performance/memory contracts. Choose the
  smallest existing checks and actual visual, listening or player observations
  that can expose the relevant failure. Pin the source and preserve failed evidence.
- **Decision and remaining gaps:** keep requirement recorded, implementation,
  technical validation, actual experience, user decision, integration and release
  separate. Apply the [evidence and acceptance gates](../testing/README.md#evidence-and-acceptance-gates)
  and record the remaining owner or approval dependency. Do not mark an unseen or
  unheard result accepted because CI passed.

Behavior-preserving code optimization retains existing editable sources and
calibration and proves the applicable Pixel Parity; no redundant GUI-authoring
sample is required. New/changed assets or export toolchains follow their domain's
editable-source proof. Intentional visual/audio changes require their own scoped
review and explicit user approval before Golden standards change. Existing save,
security and release gates remain authoritative; this gate adds no automatic
merge, deployment or broad diagnostic run.
