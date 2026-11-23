# Headless CAD

Use `import "cad";` for constructive geometry, assemblies and sampled playback.
The library runs in native Flexscript and the checked VM. It uses millimetres
at the document boundary and integer nanometres internally. It operates on
tessellated solids.

For a JSON document with `units`, `nodes` and named `parts`, call
`cg_mesh(j_parse(source))`. Check the returned object for an `error` field.
The mesh includes indexed triangles, part bounds, oriented closure and
estimated volume. Call `cg_stl(mesh)` before starting another geometry build.
On success the descriptor stores the data pointer at offset 0 and its byte
length at offset 8. A zero result means export failed.

For imperative models call `cad_begin()`, construct solids using `cad_box`,
`cad_cylinder`, `cad_sphere`, transforms and booleans, then call `cad_mesh`.
For assemblies use `cad_assembly`, `cad_assembly_check`, `cad_assembly_sweep`
or `cad_assembly_playback`. Sweeps evaluate discrete poses. An error indicates
an incomplete check.

For a software snapshot, import `cad/render.flex` and call
`cad_render_rgb(mesh, width, height, view)`. The result points to
`width * height * 3` packed RGB bytes in top-to-bottom row order.
The renderer supports orthographic `iso`, `top`, `front` and `right` views,
dimensions of 16–512 pixels per edge, and the same indexed tessellation
as STL export. On failure it returns zero with a message in `cg_error`.

From the SDK root, build and run the two-hole mounting plate regression with
the SDK source libraries selected.

```sh
FLEXSCRIPT_LIB="$PWD/libs" flexscript libs/cad/tests/geometry.flex -o /tmp/flexscript-cad-test
/tmp/flexscript-cad-test
```

## PuppyCAD projects

Import `cad/project.flex` to open and evaluate a v4 project. Pass the complete
file text to `cad_project_open`, which returns its JSON tree or zero with
`cg_error` set. `cad_project_part` resolves its selected part, falling back
to the first part for a missing selection. A selected assembly is available
through `cad_project_item` and has no active part. `cad_project_mesh` evaluates supported features in graph
order. Check its result for an `error` field, then call `cad_project_stls`
in the same build arena for one binary STL descriptor per body. Round-trip
the complete tree with `j_encode` to retain data for other features and parts.

`cad_project_set_depth(project, feature_id, value)` edits an extrusion
and rebuilds it. V4 revolve nodes sweep a selected sketch region around a
directed sketch-space axis for up to 360 degrees. Use
`cad_project_set_revolve_angle(project, feature_id, value)` to edit the
sweep in degrees. Import `cad/sketch-dimension.flex` for
`cad_project_dimension(project, entity_id, field, value)`, where `field`
is `width` or `height` and `value` is a JSON number in millimetres. The
operation preserves fixed corners, updates the driving relation and returns
the rebuilt mesh. Rejected edits return zero and preserve the input graph.

Import `cad/threemf.flex` for `cad_project_3mf(project)`. It evaluates the
selected part and returns a 3MF package containing a named model object for
each body. A v4 feature tree that merges extrusion previews or contains a revolve, loft or edge finish uses the Rust
exporter’s numbered object names (`Body 1`, `Body 2`, …). Independent
extrusions and assembly occurrences keep their authored names. The descriptor holds the byte pointer at offset 0 and the length
at offset 8. A zero result signals failure, with details in `cg_error`.

`cad_project_profile(nodes, sketch, feature)` resolves the selected v4
profile ID from the graph. It returns the outer loop followed by its holes.
Each array entry holds a counterclockwise array of sketch-space points at
offset 0 and its source entity at offset 8. Coordinates are integer nanometres.
The project evaluator extrudes those loops on a reference plane or an earlier
extrusion face. A face uses the graph's `sourceId` and `faceId`. Side IDs
follow outer edges, then clockwise hole edges, followed by bottom and top caps.
The supporting prism is rebuilt before placing dependent sketches, so depth
edits move their planes. Cuts on a face grow inward by default.
Supported closed primitives include corner and rotated rectangles, circles,
ellipses, regular polygons and capsules. Closed chains of sketch lines can
also bound a profile or hole. Edges can occur in either direction and in
any order. Open and branched line components and construction geometry are
skipped when identifying profiles. Crossing or touching boundaries fail
evaluation. Concave caps are triangulated before solid operations.

Use `cad_project_add_curve` with `diameterCircle` or `centerRectangle`
for two-point profiles. `threePointRectangle` accepts the first edge
and a point setting its signed height. `threePointCenterRectangle`
accepts the center, a side midpoint and a point setting the perpendicular
half-height. All rectangle modes store width, height and rotation in
the native rectangle primitive. The shared dimensions API edits those
values and rebuilds dependent solids.

For a regular `polygon`, provide a center and one vertex. For a `capsule`
slot, provide both cap centers and a point on the side wall. Pass the
entity and sketch IDs to `cad_project_set_profile_parameter` to change
polygon sides or slot width. It returns a new document, updates linked
profile copies, and checks dependent solids. To drive a polygon’s radius,
use `cad_project_set_curve_dimension` with the `radius` field.

Use `cad_project_add_plane_sketch(project, plane)` to add a v4 sketch on
`XY`, `XZ`, or `YZ`. It returns a new document with the sketch appended to
the selected part's graph and feature tree. Existing reference plane IDs
are reused. If a legacy part lacks the requested plane, the operation
adds it before attaching the sketch.

Import `cad/author.flex` to create a v4 part with `cad_project_new(name)`.
The initial sketch is `native-sketch-1` on the XY plane. Pass the project,
sketch ID, `"rectangle"`, `"circle"` or `"line"`, and two sketch-space points to
`cad_project_add_primitive`. Each point is a `cg_v(x, y, 0)` in nanometres.
Lines use their endpoints. Rectangles use opposite corners. Circles use a centre and rim point and
48 segments. The function appends to the graph and returns the new entity.
For an ordinary or construction point, pass `"point"` or `"constructionPoint"`,
its sketch position and `0` for the second position. Both expose a `center`
anchor for dimensions and neither contributes an edge to a solid profile.

Pass a JSON array of entity IDs to `cad_project_toggle_construction(project,
sketch_id, ids)` to convert sketch geometry. An all-construction selection
becomes profile geometry. A mixed selection becomes construction. A
successful edit returns a new project with the original entity IDs and
relations. Removing a profile needed by an extrusion fails atomically.

For a v4 part, `cad_project_pick_edge_in(project, eye, direction, tolerance, body_id)`
returns a visible straight edge as its two world endpoints and outward face
normals. The ray and optional body filter follow the face picker. Tolerance
is a world distance in nanometres. Pass an array of these references to
`cad_project_add_edge_finish(project, kind, size, references)`. Use
`chamfer` for an equal setback or `fillet` for a circular radius, with
size in nanometres. It returns a rebuilt copy. The feature re-resolves each
edge after earlier finishes, subtracts from convex corners and adds material
at concave ones. To edit the size on an existing feature, call
`cad_project_set_edge_size(project, id, value)` with a JSON number in
millimetres. A failed edit leaves the document intact.

V4 projects saved by the TypeScript editor retain their `chamfer` and
`edge` graph records. The edge selector refers to the generating extrusion,
so the bevel is cut from that tool before a join or cut. Saved selectors work
on a positive blind extrusion of one outer loop with optional apertures.
Each loop can be a corner or rotated rectangle, regular polygon, circle,
ellipse, capsule, or closed sequence of authored straight lines with
matching endpoints.
The selector uses TypeScript's original segment order, with the outer loop
first followed by each clockwise aperture in profile order. Vertical aliases
resolve to the same edge.
For a concave or pierced profile, convex edges are eligible when both
adjacent planes pass the TypeScript convexity check. The bounded half-space
cut preserves the opening or recess where it meets the bevel.
A direct corner rectangle also supports outer edge chamfers with a sampled
aperture in the profile. Its outer ordinals precede all aperture edge IDs.
Inner rim selectors work when a single unconstrained, axis-aligned
TypeScript half-ellipse and its chord reproduce the same adaptive vertex
keys, authored start and clockwise order. Ambiguous samples and changes
that require unresolved sketch relations fail the edge check. Attachment
face numbering still requires independently verified sampled-loop order.
Cap sketches retain their attachment frame, including the mirrored bottom.
The cap ordinals follow all outer and aperture sides on the supporting
extrusion. Side sketches use the original directed segment on a matching
outer or aperture wall. Concave edges, unresolved curve edge ordinals,
incompatible face numbering and inward face cuts report a feature error.
`cad_project_set_chamfer_distances(project, id, d1, d2)` takes distances in
nanometres and returns a validated copy. Pass zero for `d2` to omit it and
use `d1` for both setbacks.

`cad_project_add_loft(project, first_sketch, first_profile, second_sketch,
second_profile, operation)` creates a ruled loft between two closed profiles
on different sketches. Each profile has one outer loop. Profile numbers start
at one. Specify `newBody` or `join`. The evaluator aligns the sections in world
space, samples both perimeters at their combined corner positions, and checks
the side faces and caps for intersections. A failed rebuild returns zero
and preserves the original project.

`cad_project_add_revolve(project, sketch_id, profile, a, b, angle, operation)`
returns a rebuilt copy. The profile number starts at one. Supply the directed
axis as two sketch-space vectors in nanometres and the sweep in microdegrees.
The operation can be `newBody`, `join` or `cut`.

`cad_project_add_extrusion(project, sketch_id, profile, depth, operation)`
returns a new project tree with the feature and its history links, or zero
on failure. Profiles are numbered from 1 and depth is in nanometres.
The source project remains available for undo. The headless
`libs/cad/tests/author.flex` regression covers serialization, rebuild
failure recovery, dependent solids and duplicate feature rejection.

For an explicit extent, use
`cad_project_add_extrusion_options(project, sketch_id, profile, depth,
operation, end, flip, target_id)`. To edit the saved feature, use
`cad_project_set_extrusion_options(project, feature_id, depth, operation, end,
flip, target_id)`. Both return an updated copy and preserve the source on
failure. End conditions are `blind`, `symmetric`, `through-all` and
`up-to-body`. Depth is in nanometres. Supply zero or one for flip, and an
earlier body ID for `up-to-body`. The selected body determines the tool's
length. Cut and join still apply to the most recent active body.
`cad_project_extrusion_targets(project, feature_id)` lists evaluated earlier
bodies as JSON objects with `id` and `name`. An empty feature ID lists
targets at the end of the timeline, where a new extrusion would be added.
For camera-ray picking, `cad_project_extrusion_target_stage(project,
feature_id)` returns a temporary v4 copy evaluated at that same timeline
position. Use it for preview and selection and apply the edit to the source.

Use `cad_project_add_item(project, kind)` with `"part"` or `"assembly"` to
append and select an item in the same document. A new part has an XY sketch.
A new assembly has an empty instance list. `cad_project_insert_instance(project,
part_id)` inserts a part from that document into the selected assembly. Each
insertion gets a distinct instance ID and keeps its source part ID. The
first instance starts at the origin. Subsequent instances start with a 10 mm
gap along X from the assembled geometry. Both operations return a new tree
on success or zero on failure, leaving the source available for undo.

For a selected v4 assembly, `cad_project_mesh` evaluates the referenced parts
and places one mesh object per instance. Free instances use the saved XYZ
rotation, translation and scale. Fastened connectors and servo-driven revolute
mates determine rigid placements. Free revolute, prismatic, planar and ball
mates are solved together using damped least squares. The solver grounds the
first instance's fastened group and world-fastened groups. A conflict returns
an evaluation error. `cad_project_solve_assembly(project)` returns a copy
with the solved placements written to the mated instances. `cad_project_servo_angle(project, mate_id, microdegrees)`
returns an edited copy with the new home angle and solved transforms for the
mated instances. `cad_project_3mf` includes the instance names and assembly
title, and `cad_project_stls` returns descriptors in instance order.

`cad_project_replace_instance_part(project, instance_id, part_id)` returns
a rebuilt copy with a different part definition on the chosen occurrence.
The instance ID, authored transform, connector frames, mates and actuators
stay intact. A missing part or a failed rebuild leaves the source unchanged.

Use `cad_project_instance_transform(project, id)` to read the displayed
translation, XYZ rotation and scale, including default values.
`cad_project_set_instance_component(project, id, group, axis, value)`
updates one `x`, `y` or `z` component in `translation`, `rotation` or
`scale`. Values use millionths of a millimetre, degree or scale factor.
The returned document includes the solved assembly. Existing mates can
constrain the requested placement. A zero scale or conflicting edit fails
and leaves the source document intact.

Use `cad_project_connector_frame(project, owner, id)` to read a connector's
local `position` in millimetres and its intrinsic XYZ `rotation` in degrees.
Omitted frames default to zero. Pass an occurrence ID as `owner`, or an
empty string for a world connector. Connector IDs can repeat on different
owners. `cad_project_set_connector_component(project, owner, id, group,
axis, value)` changes one `x`, `y` or `z` axis in `position` or `rotation`
and solves the assembly. Pass position in nanometres and rotation in
microdegrees. It keeps the connector, mate and actuator references and
returns an edited copy. A conflicting edit leaves the source intact.

`cad_project_reassign_connector(project, owner, id, next_owner, next_id)`
changes the owning occurrence, the ID, or both. It preserves local frame
coordinates and updates every mate endpoint addressed by the original
owner and ID. Use an empty owner for a world connector. A duplicate on the
destination or a conflicting mate rejects the whole edit.

Import `cad/mate-author.flex` to create v4 assembly mates. Call
`cad_project_pick_mate_face(project, eye, direction, visible_id, inward)`
for each end. Pass zero for unrestricted visibility and set `inward` on
the second face. The result contains the instance ID, local position in
millimetres and local XYZ rotation in degrees. Pass these frames to
`cad_project_add_mate(project, kind, a, b)` with `fasten`, `revolute`,
`prismatic`, `planar` or `ball`. `cad_project_fasten_to_world(project,
instance_id)` attaches an occurrence to the world at its solved pose.
For assembly viewport picking, `cad_project_pick_mate_element(project, eye,
direction, visible_id, edge_tolerance, inward)` returns a local frame with
`pickKind` equal to `Vertex`, `Edge`, `Curved edge` or `Face`. The edge
tolerance uses nanometres. Visible corners take priority within 1.5 times
that tolerance. Straight edges supply their midpoint and direction. Curved
runs supply the mean of their welded vertices and their plane normal.
A closed loop has no selectable corner. Pass the two frames to
`cad_project_add_mate` to align an edge axis with its partner. Only the
local placement and occurrence reference are saved in the connectors.

Both editing calls return a solved document copy. A conflicting edit
returns zero with a diagnostic and leaves the input available for retry.

`cad_project_drive_mate(project, mate_id, microdegrees)` creates or updates
a servo for a revolute mate. An explicit zero sets a driven home pose.
`cad_project_remove_mate(project, mate_id)` removes the associated actuators
and releases each endpoint connector if no other mate uses it on that
instance. `cad_project_remove_instance(project, instance_id)` removes one
occurrence, its connectors and its attached mates and drivers. Partner
connectors and reusable part definitions survive occurrence deletion. Both
removal operations use the displayed solved placements as the starting pose
and return a new document. Removing the last instance leaves an empty
assembly that can accept another part.

For a selected part, `cad_project_pick_face(project, eye, direction)` casts
a world-space ray. Supply the eye in nanometres and a nonzero direction
with each component in ±1e9. It checks the nearest evaluated surface, then
returns its v4 extrusion face descriptor. A miss or a surface without a
matching persistent face returns zero and sets `cg_error`. This includes the
floor of an inward cut made from a face sketch. Bounded face regions include
their hole loops.

`cad_project_add_face_sketch(project, face)` validates the descriptor and
returns a copy with the face and new sketch linked into the feature graph.
Existing face records are reused. `cad_project_sketch_face_loops(project,
sketch)` returns the support outlines in sketch-local nanometres.

`cad_project_set_sketch_support(project, sketch_id, plane, face)` moves an
existing v4 sketch to a standard plane or extrusion face. Pass `XY`, `XZ`
or `YZ` and zero for the face, or pass an empty plane name and a persistent
face descriptor. The returned document keeps the sketch's local authored
geometry and feature references. Face support must precede the first
feature that consumes the sketch. Projected edges are rebuilt and the
edit is rejected if a projection would be lost. Use
`cad_project_sketch_support_stage(project, sketch_id)` for a temporary face
picker document that hides later geometry.

Import `cad/projection-author.flex` to project body edges. Call
`cad_project_project_face_edges(project, sketch_id)` for the supporting
face boundary. It recognizes circular rims and arcs and retains the line
segments of other contours. Call `cad_project_project_edge(project,
sketch_id, point, tolerance)` to pick a straight edge near a sketch-local
point in nanometres. Both return a copy with v4 `projected` relations
and ordinary sketch entities.
`cad_project_projection_guides(project, sketch_id)` supplies the corresponding
two-point paths for showing the pickable edges. The evaluator
uses the body state before the sketch's first consuming feature and rebuilds
linked geometry on a scratch graph. `cad_project_rebuild_projections(project)`
returns a document with the projected entities updated for editing or saving.

`cad_sketch_snap_projected_edges(nodes, sketch, point, tolerance)` returns
the nearest point on a projected line when it is within the supplied
sketch-space tolerance. Both the point and tolerance use nanometres.
An active straight projected outline can be divided by drawing lines that end on
it or cross it. The bounded regions become selectable extrusion profiles.
Shared edges separate adjacent regions, and enclosed holes stay with their
containing region. Simple profiles retain their existing ordinals when the
outline does not need subdivision.

`cad_project_surface_hit(project, eye, direction)` picks the nearest surface
of a part or assembly, including a machined surface without a sketch face ID.
The result stores the world point in nanometres, its normal scaled by 1e9 and
the evaluated body. An assembly body identifies the individual occurrence.
A miss returns zero. `cad_project_servo_frame(project, instance_id)` resolves
a picked v4 occurrence or its fastened parent to the independent servo's
world frame, actuator and revolute mate. `cad_project_hinge_followers(data,
mate)` returns the rigidly moving occurrences or zero when a drag needs
a solved preview.

## Standalone PCAD documents

`cad_project_open` and `cad_project_mesh` also accept the Biscuit standalone
studio's `puppycorp.pcad` schema version 1 in millimetres. Evaluation copies
the authored tree before expanding linked boards, modules, parameter bindings
and assembly instances. The mesh carries the standalone evaluator's mechanical
reports, including occurrence transforms, joint frames and physical routes.

Import `cad/project-line-edit.flex` for straight-line Trim and Extend.
Call `cad_project_trim_line(project, sketch_id, line_id, point, tolerance)`
or `cad_project_extend_line` with the same arguments. The point is local
to the sketch and the tolerance is in nanometres. Boundaries include finite
lines, circular and elliptic curves, rectangles, polygons, slots, and control,
open fit and periodic fit splines. Spline contacts come from the cubic curves
and include tangencies. Editing preserves surviving endpoint references and
returns a validated new graph.
A failed dependent solid rebuild leaves the original drawing intact.

Import `cad/project-arc-edit.flex` for `cad_project_trim_circular_curve` and
`cad_project_extend_circular_arc`. Both take the project, sketch ID, curve
ID, sketch-local click and tolerance in nanometres. Trim works on a circle
or finite circular arc. Extend retains the supporting circle and signed
sweep direction while lengthening the selected arc end. Boundaries include
finite lines, circular and elliptic curves, polygons, slots and cubic splines.
Compatible references follow the retained fragments. A failed rebuild leaves
the original drawing intact.

`cad/project-ellipse-edit.flex` exposes `cad_project_trim_elliptic_curve`
and `cad_project_extend_elliptic_arc` with the same sketch-space arguments.
Retained elliptic fragments share their supporting ellipse through the
`sameEllipse` relation. Extension changes the selected end and preserves the
signed sweep direction, center, axes and rotation.

`cad/project-spline-edit.flex` provides `cad_project_trim_spline` and
`cad_project_split_spline` with the same arguments. These return open control
chains for the retained cubic spans. Splitting a closed fit spline opens it
at the chosen point. An interior split of an open spline joins the pieces by
a saved endpoint coincidence. Surviving references follow their original
points. A Normal or Point on curve relation keeps its ID on the first retained
portion containing its contact. Trimming away the contact removes the relation.
Edits that require replacing a fixed handle during Split or cannot preserve a
dependent feature return an error and keep the saved model intact.

Use `cad/continuity.flex` to check physical continuity in a standalone
PCAD document. `pcad_trace(document, request)` reports the ordered path
and all reachable conflicts. `pcad_required_traces(document)` evaluates
the authored required paths and distinguishes an open connection from
an unresolved path. Both use actual copper on each board and explicit
contact maps, wires and splices.

Use `cad/harness.flex` with the resolved PCAD and evaluated assembly mesh.
`pcad_harness_pose(document, mesh)` reports route, splice and jacket
findings at that pose. `pcad_harness_document(document, pose)` builds a
wire schedule and pinouts in review or manufacturing mode and checks
specified cuts and endpoint preparations. `cad/harness-pdf.flex` appends
these sheets to a PDF drawing set. The build caller supplies the frozen
source and manifest digests used in the published report and footer.

Import `cad/schematic-print.flex` to render standalone PCAD schematics.
`cad_pcad_schematic_pdf(document, sheet_id, revision)` prints one sheet.
Use `cad_pcad_schematic_selection(document)` to read the ordered release
selection and `cad_pcad_schematic_pages(document, selection, revision)` to
prepare its pages for `pcad_harness_pdf`. The result includes an evidence
row for each requested sheet and is valid when every sheet resolves.

Import `cad/circuit.flex` for ideal linear circuit analysis and
`cad/spice.flex` for exchange. `pcad_circuit(document, experiment_id)`
returns DC, transient, AC or sweep samples from the authored experiment.
`pcad_spice(document, experiment_id, case_index, manifest_hash, source_hash)`
returns the corresponding ngspice deck and source identity. Descriptive
labels stay out of the deck's solver tokens. The transient timing helper
uses the same fixed-step plan as the solver.

Use `cad/studio/pcad-solid-clearance.flex` to check an occurrence pair at
its authored pose or at named mate samples. `pcad_solid_clearance(document,
experiment)` reports signed status, measured gaps and witness points.
`pcad_route_motion(document, settings)` in
`cad/studio/pcad-route-motion.flex` reports a selected conductor's route
length, clearance and bend findings at each sample. Both keep the
original assembly intact and accept the original schema 1 study records.

Import `cad/electrical/pcb-model.flex`, `cad/electrical/check.flex` or
`cad/electrical/kicad.flex` to compile PCB layouts, check routed copper and
write editable KiCad files. The model supports plated two-, three- and
four-pad headers and front or back oval SMD pads. The checker uses the
actual layers, drills, board outline, net rules and zones in the input.
`cad/electrical/cad.flex` builds the drilled substrate and mounted body
envelopes. `pcb_render_rgb` in `cad/electrical/render.flex` returns raw
RGB24 copper-layer previews.

Import `cad/linked-boards.flex` to project the boards in a standalone PCAD
assembly. `cad_pcad_board_count(document)` reports the selected board count
from one through eight, or zero for a missing or malformed board collection.
`cad_pcad_linked_boards(document, mesh)` returns a `manifest` and a `boards`
array in the authored board order. Pass the evaluated mesh for the same
document to reuse its poses, or pass zero to evaluate them. The manifest
keeps board IDs, board-local placements, logical pin and net IDs, and each
linked occurrence's world transform. Each board row contains its ID and
either a PCB checker input in `source` or a scoped `error`. A document whose
board identities or assembly links cannot be resolved returns zero with
`cg_error`. Entries for classified nets include `routing_rules` with their
canonical net and class IDs and the effective clearance. The caller runs PCB
checks and writes artifacts.

Import `cad/studio/pcad-copper-review.flex` for `pcad_copper_review`,
`pcc_zone_view` and `pcad_board_rules`. These take a standalone document
and a zero-based board index. Use `-1` for the topology-only copper review.
The zone view also takes the authored zone ID. The rule report uses the same
projected inputs and native checker as a frozen build.

Import `cad/product-bom.flex` for `cad_pcad_product_bom(document)` and the
matching CSV writers `cad_pcad_product_bom_csv` and
`cad_pcad_wire_stock_csv`. Each CSV writer takes its checked report and the
frozen manifest and source SHA-256 digests. `pdb_interactive(input)` exposes
the original paginated product and stock views.

Import `cad/studio-edit.flex` for direct scalar edits and occurrence pins.
Import `cad/studio-history.flex` to inspect the effective feature order with
`cad_studio_feature_history(project)`, suppress or restore a modifier using
`cad_studio_suppress_feature(project, id, suppressed)`, and move a feature
by one slot using `cad_studio_move_feature(project, id, delta)`. The two
edits return validated document copies. Call `cad_studio_earlier_features`
with a part ID for its earlier output nodes and `cad_studio_preview_feature`
with a part and earlier node ID to evaluate a temporary mesh.

`cad_studio_properties(project)` lists driving fields in document order with
joints first. `cad_studio_set_property(project, index, value)` takes millionths
of a millimetre or degree. `cad_studio_toggle_fixed(project, occurrence_id)`
captures the solved world transform or removes the existing pin. Both return a
rebuilt document copy on success and zero on failure. `cad_studio_hinge`
resolves a selected occurrence against the evaluated mesh for native dragging.

`cad_studio_add_shell(project, part_id, side, thickness)` appends a Shell
modifier to a standalone output part. `cad_studio_set_shell(project, feature_id,
side, thickness)` edits an existing Shell in place in the returned copy. Use
`x`, `-x`, `y`, `-y`, `z` or `-z` for the opening in the part's local axes and
pass the wall thickness in nanometres. The output part keeps its identity and
the source remains an earlier feature. Invalid geometry returns zero with
`cg_error`. The SDK rebuilds the complete design before returning the edit.


For an isolated view, `cad_project_surface_hit_in(project, eye, direction, id)`
and `cad_project_pick_face_in(project, eye, direction, id)` restrict the ray
to one body ID or assembly occurrence path. Zero includes every body.
A sketch support returned by the face picker belongs to the hit body.

## Faceted STEP

Import `cad/step.flex` and call `cad_project_step(project)` for deterministic
AP214 text. The returned buffer holds its data pointer and byte length in the
first two words. A failure returns zero with a diagnostic in `cg_error`.
Assembly exports retain reusable part definitions, occurrence IDs and local
placements. A scaled or mirrored v4 instance uses a scaled part definition.
The standalone checker can call `pcad_step(doc, mesh, source_hash)` to attach
the frozen bundle's SHA-256 and receive definition and occurrence counts.
The writer supports closed, positively oriented faceted shells up to 2 MiB.

Import `cad/step-document.flex` to read a faceted Part 21 exchange. Pass its
text to `cad_step_read` and the returned file handle to `cad_step_bodies`
to list entity IDs and display names in file order. Pass the handle, an ID,
the source basename and the SHA-256 of the exact input bytes to
`cad_step_shape`. The result is a validated PCAD faceted node with its
source provenance. The reader converts SI length units to millimetres,
triangulates planar outer loops, checks the declared plane and validates
the oriented shell. Its limits match the standalone reader at 2 MiB,
50,000 entities, 128 body definitions, 256 vertices and 512 triangles
per imported body.

`cad_step_apply(document, shape, replacement_id)` returns an evaluated
document copy. Pass zero for the document to create a mechanical design.
With an empty replacement ID it appends a part and, in an assembly, a fixed
occurrence. A faceted node ID replaces its geometry and provenance while
retaining references and other fields.

Import `cad/step-assembly.flex` to read reusable definitions and placements.
`cad_step_hierarchy(file)` returns the root, direct occurrences, shared
parts, subassemblies and expanded occurrence counts. Fixed-mate frames use
millimetres and Euler angles in degrees. `cad_step_assembly(file, filename,
digest)` builds a new mechanical document. `cad_step_adopt(document, file,
filename, digest)` accepts an empty design or the original Biscuit starter
and returns a copy. Both entry points validate the complete assembly before
returning it. A STEP placement records the saved pose as a fixed mate.

## PuppyCAD sketch curves

V4 circular arcs, rotated elliptic arcs and fit and control splines contribute
their sampled edges to profile tracing. `cad_sketch_paths(nodes, sketch_id)`
returns the same curves for the native sketch canvas. Open fit splines use
natural end conditions. Closed fit splines use periodic end conditions.
Control splines use cubic Bézier spans with 3n + 1 control points. Both use
the reference editor's 0.01 mm subdivision tolerance.

Elliptic arcs load from the TypeScript `sketchArc.arc` node or the older
`sketchPrimitive.primitive` node. The TypeScript node uses adaptive chords
with a 0.01 mm error bound. The older node retains its saved segment count
and existing tessellation. Both use the same analytic editing tools, which
preserve the stored node wrapper and entity ID.

Use `cad_project_world_sketch_paths(project, ids)` for a v4 part viewport.
Pass a `cg_array()` of sketch ID strings in display order. Each returned
record carries a world-space point array in nanometres, the closed-path
flag and the original entity. Reference planes need no solid. Sketches
whose supporting face is unavailable are omitted while the other requested
paths remain available. Geometry errors return zero with `cg_error`.

Import `cad/author.flex` and call
`cad_project_add_curve(project, sketch_id, kind, points)` with sketch-space
point vectors in nanometres. Supported kinds are `arc`, `fit`, `control` and
`periodic`. An arc takes its start, a point on the arc, and its end.
The function returns the inserted sketch entity, or zero with `cg_error`.

## Editing v4 lines and point dimensions

Import `cad/project-lines.flex`. `cad_project_line_sketch(project, sketch_id)`
reports each line's saved ID, solved endpoints and length in millimetres, the
sketch's degrees of freedom and any redundant constraint IDs. It accepts
sketches containing lines, circles and point primitives, including construction geometry.
Each line uses two of the 32 available anchors. Horizontal and vertical
relations, driving lengths, fixed and coincident anchors, signed X/Y
distances and direct distances are supported. The solver accepts 32 segments
including those used by driving distances, and 64 constraints including the
temporary edit pin. The report includes solved point centres in `points` and
individual measurements with both endpoints in `distances`. V4 `symmetric`
anchor pairs and linked mirrors of points, lines, circles and circular arcs use
the shared symmetry solver. Moving either side reflects the other across the
axis. Mirrored circles share a radius. Mirrored arcs share a radius and sweep
magnitude, with opposite sweep signs and reflected start angles. The saved
`mirror` relation keeps the same fields for each entity kind.
`cad/project-mirror-author.flex` exposes
`cad_project_mirror_entity(project, sketch_id, entity_id, axis_id)` and
`cad_project_toggle_point_symmetry(project, sketch_id, a, b, axis_id)`.
Both return an edited copy and validate downstream features. A circle contributes
one centre anchor and one additional radial degree of freedom until its size
is driven. Its diameter and radius appear in `radial`.

Import `cad/project-line-directions.flex` to call
`cad_project_toggle_line_direction(project, sketch_id, source_id, target_id, kind)`.
Use `parallel` or `perpendicular` with two straight lines. Adding the relation
holds the picked source and solves the follower with its length, coincidences
and other active constraints. The v4 relation preserves both entity IDs and
is validated during reopen and manufacturing. The function returns an edited
copy, or zero when the constraints or dependent feature cannot rebuild.

Call `cad_project_toggle_equal_lines(project, sketch_id, source_id, target_id)`
from the same module to match two straight-line lengths. The line pair retains
its existing directions and coincidences. A driving length expression or
variable on either line sets the shared length. Incompatible dimensions are
rejected atomically.

Import `cad/project-concentric.flex` for
`cad_project_toggle_concentric(project, sketch_id, source_id, target_id)`.
Circles, circular arcs, ellipses and elliptic arcs can share a center while
retaining their size, orientation and sweep. A distance dimension or a drag
can move the shared center. The v4 relation retains both curve IDs and is
checked when reopening and manufacturing. Adding it holds the picked source
center and rejects incompatible constraints on a copy of the drawing.

Import `cad/project-tangent-author.flex` for
`cad_project_toggle_circular_tangent(project, sketch_id, source_id, target_id, internal)`.
It links whole circles and finite circular arcs using the sum or difference of
their radii. For internal contact, pass the outer curve first. Both signed
sweeps must contain the contact. The existing radius and diameter fields move
the centers through the tangent relation, with a supported center separation
of 0.01 to 500 mm. Reopen and manufacturing check the saved contact. A failed
solve or rebuild preserves the original drawing. When either radius is free,
the reported degrees of freedom are an upper bound.

Use `cad_project_toggle_curve_tangent(project, sketch_id, source_id, target_id)`
from the same module for external tangency between a straight line and a
circle, circular arc, ellipse or elliptic arc, or between two circular
curves. The contact lies on the line's supporting line and can fall beyond
either endpoint. For an arc, the contact must be within its signed sweep.
An ellipse's width, height and rotation dimensions and their variables update
that contact. The two pick orders preserve the selected source during
authoring, and the v4 `tangent` keeps the original `a` and `b` entity IDs.
Reopen and manufacturing check saved contacts, and edits that break the
contact or a dependent feature are rejected.

Import `cad/project-midpoint-author.flex` for
`cad_project_toggle_midpoint(project, sketch_id, curve_id, anchor)`. It ties
an existing point, line endpoint or supported primitive center to the middle
of a straight line, circular arc or elliptic arc. The saved v4 relation has
`a` set to the `{entityId, point}` anchor and `b` set to the source curve ID.
An arc uses the middle of its signed angular parameter interval. Source
dimension edits move the follower, and reopen and manufacturing validate the
saved contact before using the sketch.

Import `cad/project-point-on-curve-author.flex` for
`cad_project_toggle_point_on_curve(project, sketch_id, curve_id, anchor)`.
It attaches an existing sketch anchor to a straight line segment, circle,
ellipse, circular arc, elliptic arc, or spline. The anchor can slide along the curve.
Dragging uses the nearest point on the actual curve. A finite segment or
signed arc includes both endpoints. Driving radius, width, height, rotation
or sweep edits move the attached anchor, and incompatible constraints reject
the edit. The v4 `pointOnCurve` relation stores the
`{entityId, point}` anchor in `a` and the source curve ID in `b`.
Open control, open fit, and periodic fit splines use the original cubic spans
for contact. The editable follower slides without changing the spline's
stored controls. At an exact crossing the relation stores only the shared
position, with the first equally near span used for the local tangent.
`cad_project_move_smooth_point` also moves attached followers after editing
a source spline handle. It preserves the other controls and rejects a source
edit if a follower cannot meet its existing constraints.

Import `cad/project-normal-author.flex` for
`cad_project_toggle_normal(project, sketch_id, curve_id, anchor)`. A Normal
relation puts `a.entityId`'s line endpoint (`p0` or `p1`) on a separate straight
line, circle, ellipse, arc or spline `b` and makes the line perpendicular to
the analytic tangent there. The solver and manufacturing check the finite
curve. For fit and control splines, a contact requires a nonzero tangent and
matching tangents on adjacent spans at an internal join. Line dimensions and
source handle edits retain the original relation. The degree count is an upper
bound when the source spline has free controls outside the line solve.

Line dimensions can coexist with `smoothJoin` relations on lines and circular
arcs. Editing a line's driving length or its variable keeps the first endpoint
fixed and moves the joined curves to preserve the shared endpoints and tangents.
The edit is rejected if the result breaks another driving constraint or a
dependent feature. In this case `degrees_of_freedom_is_upper_bound` identifies
an estimate that excludes the rank of the smooth equations.

`cad_project_set_circle_dimension(project, sketch_id, circle_id, field, text)`
accepts `diameter` or `radius` and a length expression. Changing a size
updates the saved primitive and its measured counterpart. A newly failing
feature rejects the edit. Use `cad_project_toggle_circle_reference` or
`cad_project_remove_circle_dimension` with the same first four arguments.
Circle centres also work with point distances and dragging. Both manufacturing
and the editor check saved driving values against the primitive and formula.

Use `cad_project_set_curve_dimension` for a circular arc’s `radius` or
`arcSweep` and an elliptic arc’s `arcSweep`. Sweep expressions accept
degrees and radians, with signed degree values in saved relations and radians
in the arc geometry. Zero and full turns are invalid. Use
`cad_project_toggle_curve_reference` and `cad_project_remove_curve_dimension`
to change or remove annotations. These calls also accept circle fields.

`cad_project_set_line_length(project, sketch_id, line_id, length_nm)`
keeps the start point and updates or creates the driving dimension.
`cad_project_move_line_endpoint(project, sketch_id, line_id, end, position)`
takes `p0` or `p1` and a JSON point with x and y in millimetres. It holds the
opposite endpoint and projects the requested point onto the allowed motion.
`cad_project_move_point(project, sketch_id, point_id, position)` takes the
same millimetre position for an ordinary or construction point. Fixed points
reject a drag. Other points follow the pointer along the motion their
driving dimensions allow. These operations return an edited document copy
or zero with `cg_error`.
A numeric edit preserves the constraint representation. Use
`cad_project_set_line_expression(project, sketch_id, line_id, text)` for a
driving expression such as `#width / 2 + 1 mm`. A plain number clears the
expression. As in the Rust editor, annotating a graph dimension moves it to
the sketch's inline relations. Its ID and metadata travel with it.

`cad_project_add_point_distance(project, sketch_id, a, b, axis, reference)`
takes two v4 anchors, each with an entityId and point name (p0, p1 or center).
Pass x or y for a signed axis, or an empty string for the direct distance.
`cad_project_set_distance_expression(project, sketch_id, id, text)` holds
the first anchor. A reference reports the current measurement and leaves
the solve unchanged. Toggle it with `cad_project_toggle_distance_reference`
or delete it with `cad_project_remove_point_distance`, both taking the
project, sketch ID and relation ID.

`cad_project_edit_line_variable(project, sketch_id, previous, name, text)`
returns a document copy with dependent driving lengths and endpoints rebuilt.
Pass an empty previous name to create a variable. An empty expression removes
an unused variable. Renaming updates exact variable references in both
dimensions and variable definitions. The evaluator supports arithmetic,
parentheses, pi, scalar/length/angle variables, metric and imperial lengths,
degrees and radians. Cycles, unknown references, incompatible units and
inconsistent saved values produce diagnostics.

## PuppyCAD feature history

`cad_project_feature_history(project)` evaluates the selected v4 part. Its
`features` array contains an ID, name and state for every feature in graph
order. States are `active`, `suppressed`, `rolledBack` and `error`. A failed
feature carries a diagnostic in `message`. Independent later features still
contribute to the preview `mesh`. A completely empty preview omits that field.
The manufacturing functions report evaluation errors on the active timeline.

Import `cad/author.flex` to edit history. `cad_project_suppress_feature(project,
id, suppressed)`, `cad_project_roll_to(project, count)`,
`cad_project_move_feature(project, id, step)` and
`cad_project_delete_feature(project, id)` return edited document copies
or zero with `cg_error`. Deletion keeps the source sketch and checks
downstream feature and projection dependencies. A rollback count of zero hides every feature. Passing
the full count restores the end of the tree. A step of −1 or 1 moves a feature
one place and updates the graph, root list and tree order together.

TypeScript PartBuilder v4 parts can store `features` and `solidSteps` in
place of a CAD graph. The shared evaluator reads their original sketch
entities and ordered extrusion, revolve, circular loft and loft shell
operations. It supports join, cut and intersection, including translated
face attachments and through-all tools. Extra `solidSteps.regions` are
closed primitives that share the primary profile's frame, extent and taper.
The region union forms one tool for the step's Boolean operation. Nominal
face attachments keep the primary profile's saved numbering. Update an
existing filled region with fields such as `region-1-center-x`,
`region-1-width` or `region-1-to-y`. The index is its one-based position
in `regions`. The native editor and shared SDK preserve the original
records on numeric, operation, extent and order edits. Import
`cad/project-legacy-edit.flex` for `cad_project_legacy_step_fields(project, id)`,
`cad_project_edit_legacy_step(project, id, field, value)` and
`cad_project_move_legacy_step(project, id, delta)`. Edits return a validated
copy. The shell keeps its original loft reference, applies wall thickness
normal to the side, and extends its cut through the rim. Saved profile
chamfers and sampled fillets modify the exterior extrusion loop or the
revolve outline in order. Selective extrusion finishes use TypeScript's
corner order for primitive and line loops. Sampled curve chains need a
matching saved outline to resolve their corner indices. Interior extrusion
loops retain their geometry, and overlapping setbacks fail evaluation.
Edit an existing finish with `finish-1-radius` or `finish-1-segments`, where
the number is its one-based position in `finishes`. Segment counts apply to
fillets. Saved topology edge finishes resolve the original extrusion edge
ordinal before combining the finished tool with earlier steps. Edit their
fields through `edge-finish-1-radius`, `edge-finish-1-segments` or
`edge-finish-1-distance2` as applicable. Older chamfer features expose
`feature-chamfer-1-d1` and `feature-chamfer-1-d2` and keep their original
feature records. A tapered wall can be finished where both nominal edge
endpoints still lie on the two supporting planes.

Import `cad/project-legacy-sketch.flex` to edit a legacy TypeScript sketch.
`cad_project_legacy_sketch(project, sketch_id)` reads the authored record.
`cad_project_legacy_sketch_view(project, sketch_id)` makes a temporary v4
sketch for the native solver. It includes the original entity IDs, variables,
and relations. Face-attached sketches open in local coordinates.
`cad_project_apply_legacy_sketch(project, sketch_id, view)` writes line, circle,
rectangle, point, circular arc, elliptic arc, spline, ellipse, capsule and
regular polygon edits into the original records. Arc edits retain the original
flat entity or nested `sketchArc`
record, its ID, and additional metadata. Edit existing fit and cubic control
spline positions through `cad_project_move_smooth_point`. The original spline
mode, closure, point indices, and metadata remain in the saved entities.
Spline profiles are sampled in millimetres using the TypeScript 0.01 mm
chord tolerance before converting to mesh coordinates. Apply rebuilds
TypeScript vertices, loops, and profiles and validates the dependent solid
before returning an edited copy. Sketch-only files can save without a solid.
Use `cad_project_set_curve_dimension` on the temporary sketch for ellipse
axes and rotation or polygon radius and rotation. Use
`cad_project_set_profile_parameter` for polygon side count and capsule
width. A saved width dimension keeps its ID and can take a length
expression. The legacy sketch Dimensions report includes its width,
including the saved expression, if present. Update a driving variable
with `cad_project_edit_line_variable` or the dimension itself with
`cad_project_set_curve_dimension`. Reference widths remain measured.
`cad_project_move_capsule_endpoint(project, sketch_id, id, end, position)`
moves a `from` or `to` endpoint and updates measured distances and
linked copies. One driving center-to-center distance lets the capsule
rotate while preserving its length. If the other endpoint is free, it can
also move to satisfy that distance. An incompatible cursor position, a
fixed selected endpoint, or a span coupled to other driving geometry
refuses the edit. Direct profile caches use the original TypeScript sampling
order. Apply preserves the primitive record and refuses edits that would
redirect a dependent face, numbered edge or selected profile corner.
Use `cad_project_add_pattern`, `cad_project_set_pattern` and
`cad_project_move_pattern_center` on the temporary sketch to author or edit a
linear or circular pattern. Apply retains the original source and relation
IDs, the IDs of surviving grid cells or circular positions, and any saved
center anchor. New instances use the original TypeScript copy prefixes.
An edit fails if a saved extrusion would select a different outline, or if
a pattern or sampled curve edit would change the cap ordinal or side used by
a face-attached sketch. Pattern edits also preserve the boundaries selected
by numbered edge finishes. A spline point edit must still satisfy any saved
coincidences.
The view can display additional shapes and unsolved records. Writing those
sketches requires support for their geometry and constraints. The temporary
graph never enters the saved file.

## Inspecting saved drawings

`cad_project_inspect_source(text)` recognizes v4 project files and standalone
`puppycorp.pcad` documents. It returns the parsed `document` and, for a
recognized but unsupported drawing, a `readOnly` reason. The report identifies
the item and node when available. The check includes inactive parts, suppressed
features and records after the rollback bar. Additional JSON metadata is
preserved. Invalid JSON and unrelated formats return zero with `cg_error`.

`cad_project_read_only_mesh(report)` builds a display preview on a copy of
the document. In a v4 part with an unsupported solid it evaluates the preceding
features up to the saved rollback bar. Unsupported schema versions have no
geometry preview. Use the original input bytes to copy a read-only drawing.

For new v4 offsets, import `cad/project-offset-author.flex` and call `cad_project_add_offset(project, sketch_id, source_id, distance_text)`. One selected line follows the connected source chain up to a fork. A positive distance expands a closed chain. Supported single sources include lines, circular arcs, circles, rectangles, regular polygons and capsules. The call returns a new drawing on success and preserves its input on failure.

For existing v4 sketch offsets, `cad_project_line_sketch` exposes signed dimensions in `offsets`. Pass a relation ID and a distance in document units or with explicit length units to `cad_project_set_offset_distance`. Edits rebuild dependent copies, including mitered chains, and reject collapsed edges before saving.

For sketch patterns, import `cad/project-pattern-author.flex`.
Pass the document, sketch ID, an array of source entity IDs, and a settings
object to `cad_project_add_pattern`. A `linearPattern` accepts `columns`,
`rows`, `step` and `rowStep` in sketch coordinates. A `circularPattern`
accepts `count`, a signed `angle` in degrees and a `center`. An optional
`centerAnchor` follows the named sketch point. Use `cad_project_set_pattern`
with the relation ID and the settings to change. Resizing keeps surviving
grid cells by row and column, or by ordinal for a circular pattern. A full
turn omits the duplicate last position. Source edits regenerate the copies.
Use `cad_project_move_pattern_center(project, sketch_id, relation_id, position)`
to move a free center or its referenced sketch anchor. A successful move
regenerates the copies and retains the reference.

## Smooth sketch joins

Import `cad/project-smooth-author.flex` for `cad_project_add_tangent_arc`,
`cad_project_toggle_smooth_join` and `cad_project_move_smooth_point`.
An endpoint names its `entityId` and `point`. Lines, circular arcs and
finite elliptic arcs use `p0` and `p1`. Open fit and control splines use their
first and last `pointN`. Moving an interior spline point or an arc center can
also move neighboring curves to maintain their common tangent. Positions use
sketch millimetres. These edits return a new document on success. Edits that
require deforming a closed chain still require the reference editor.

An elliptic arc uses its analytic tangent with the saved rotation and
signed sweep. Full-turn arcs have no join endpoints. Driving width, height,
rotation or sweep edits carry the joined curves while preserving their
geometry. The existing `smoothJoin` stores both selected anchors, and the
edit rejects incompatible driving relations or broken dependent features.

For three-point profiles, call `cad_project_add_curve(project, sketch_id,
kind, points)` with three sketch-space vectors in nanometres. For
`"ellipse"` the points are the center, first axis endpoint, and a point
whose perpendicular distance sets the second radius. For
`"threePointCircle"` all three points lie on the rim. These produce regular
v4 sketch primitives, with 128 and 64 segments respectively.

Use `cad_project_set_curve_dimension(project, sketch_id, entity_id, field, expression)`
to drive the `width`, `height` or `rotation` of a full ellipse or elliptic
arc. Width and height are full axis lengths. Rotation is counterclockwise
in sketch coordinates. Angle expressions accept degrees and radians. A
numeric edit preserves existing graph-backed width and height records.
Adding a formula or switching to reference mode carries the original ID
and metadata into the sketch relation.

`cad_project_split_ellipse(project, sketch_id, entity_id, first, second, tolerance)`
takes two rim picks on a full ellipse, or one interior pick and a null `second`
on an elliptic arc. Picks are XY vectors in sketch nanometres. Tolerance is
the picking radius in nanometres. The function returns a new project. The
original ID identifies the first piece. A v4 `sameEllipse` relation keeps
the center, both axes and rotation shared across repeated splits. Explicit
coincident cut points in web-authored drawings also follow sweep changes.

Import `cad/drawings.flex` to render the mechanical sheets of a standalone
PCAD document. `cad_drawing_pdf(document, revision_label)` returns the byte
pointer and length in the first two fields of a vector. It projects the
current model, including sections, detail callouts, hidden edges and
exploded assembly views. Invalid or unresolved sheets fail the export.

`cad_drawing_edit_sheet(document, id, settings)` creates a projection when
`id` is empty or edits the named sheet on a copy. Pass a JSON object with
`name`, `axis`, `target`, `scale`, `visibility` or `section_mm`. A null section
depth returns to a projection. On a detail sheet, edit its name or
`magnification`. The result contains the updated `document` and its projected
`scene`. An error returns zero and leaves the input unchanged. The edit
also validates any detail views that reference the changed sheet.
