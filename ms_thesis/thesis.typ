#import "template.typ": *
#set math.equation(numbering: "(1)")
#show: ams-article.with(
  title: "TITLE",
  authors: (
    (
      name: "Rahul Kumar",
      department: [Department of Electrical Engineering and Computer Sciences],
      organization: [University of California, Berkeley],
      location: [Berkeley, CA 94709],
      email: "rahulkumar@berkeley.edu",
    ),
  ),
  abstract: lorem(100),
  bibliography-file: "refs.bib",
)
// Display block code in a larger block
// with more padding.
#show raw.where(block: true): block.with(
  fill: luma(240),
  inset: 10pt,
  radius: 4pt,
)


= Introduction
== Acknowledgements

I would like to thank:
- Rohan Kumar, for his significant contributions to the work presented in this thesis.
- Bora Nikolic, for his advice and unwavering support.
- Felicia Guo, for designing the StrongARM latches used in SRAM22.
- Dan Fritchman, for his `layout21` library, upon which Substrate's GDS importing/exporting functions are built.
- Harrison Liew and Nayiri Krysztofowicz, for their work on integrating SRAM22 into digital flows.
- Arya Reais-Parsi and Aviral Pandey, for their ideas on how to improve tooling for analog design automation.

== Motivation
== Thesis Organizaition
This thesis is divided into 3 chapters. Chapter 2 introduces Substrate and describes some of its functionality. Chapters 3 and 4 present example circuit generators that were implemented in the Substrate design environment. Chapter 3 describes SRAM22, an open-source SRAM generator for the Skywater 130nm process. Chapter 4 describes the design of a transmitter for use in a UCIe link.

= Substrate

Substrate is a framework for writing circuit generators in the Rust programming language.
It is primarily intended for designing analog/mixed-signal and custom digital circuits.
This chapter presents the overarching principles behind Substrate, as well as a high-level description of its most important features.

== Architecture
=== Guiding Principles

Substrate aims to adhere to a few guiding principles:
- Performance is flexibility. This holds true for both software and hardware.
- Good APIs allow you to be lazy.
- Methodology as a library. Substrate aims to be unopinionated about how you design and lay out your circuits.
  Frameworks that more rigidly prescribes how circuits are designed (eg. a library for strictly gridded layout)
  can be written as libraries using the lower-level primitives in Substrate.
  Substrate PDK plugins, for example, are simply libraries that implement a set of required functions.
  Substrate itself is a library, which means that it can be used in any Rust project or library by simply adding it to a Rust project's dependency list. Consequently, there is no such thing as a "Substrate workspace."

=== Contexts

Substrate holds all state in a data structure called a *context*.
The context caches circuits that have been generated, and stores a handle to plugins (eg. for simulation or LVS) that have been initialized.
The context is thread safe and internally synchronized, so users can run multiple Substrate generators in parallel.

=== Components

The primary building block in Substrate is a *component*.
Substrate components are analogous to "cells" or "modules" in other design systems.
Components accept a set of parameters, and produce zero or more *views*.
Substrate currently supports schematic and layout views, though other views will likely be added in the future.

In the Rust language, a type is considered a component if it implements the `Component` trait shown below:
```rs
pub trait Component: Any {
    type Params: Serialize;
    fn new(params: &Self::Params, ctx: &SubstrateCtx) -> Result<Self>
    where
        Self: Sized;
    fn name(&self) -> ArcStr {
        // ...
    }
    fn schematic(&self, ctx: &mut SchematicCtx) -> Result<()> {
        // ...
    }
    fn layout(&self, ctx: &mut LayoutCtx) -> Result<()> {
        // ...
    }
}
```

Components can contain instances of other components.

Substrate can perform the following operations on components:
- Export a schematic to a SPICE netlist
- Export a layout to GDS.
- Run LVS, DRC, or PEX, if an appropriate tool plugin is installed.

=== Testbenches
All testbenches are components with schematic views. This schematic view should be used to instantiate voltage sources and the block being simulated.

Testbenches must also implement the `Testbench` trait, which provides hooks for:
- Setting up simulator analyses
- Including external libraries, if necessary
- Processing simulator output data

Substrate testbenches are expected to provide the name of their ground net.
Prior to simulation, Substrate will connect this net to the global ground net of the simulator (typically node `0`).

=== Process Development Kits <pdks>

Process development kits (PDKs) are ordinary Rust libraries that provide a type implementing the `Pdk` trait shown below:

```rust
pub trait Pdk {
    fn name(&self) -> &'static str;
    fn process(&self) -> &'static str;
    fn lengths(&self) -> Units;
    fn voltages(&self) -> SiPrefix;
    fn layers(&self) -> Layers;
    fn supplies(&self) -> Supplies;
    /// Retrieves the list of MOSFETs available in this PDK.
    fn mos_devices(&self) -> Vec<MosSpec>;
    /// Provide the SPICE netlist for a MOSFET with the given parameters.
    ///
    /// The drain, gate, source, and body ports are named
    /// `d`, `g`, `s`, and `b`, respectively.
    fn mos_schematic(&self, ctx: &mut SchematicCtx, params: &MosParams) -> Result<()>;
    /// Draws MOSFETs with the given parameters
    fn mos_layout(&self, ctx: &mut LayoutCtx, params: &LayoutMosParams) -> Result<()>;
    /// Draws a via with the given params in the given context.
    fn via_layout(&self, ctx: &mut LayoutCtx, params: &ViaParams) -> Result<()>;
    /// The grid on which all layout geometry must lie.
    fn layout_grid(&self) -> i64;
    /// Called before running simulations.
    ///
    /// Allows the PDK to include model libraries, configure simulation
    /// options, and/or write relevant files.
    fn pre_sim(&self, _ctx: &mut PreSimCtx) -> Result<()> {
        Ok(())
    }
    /// Returns data that should be prepended to generated netlists,
    /// depending on the netlist purpose and the process corner.
    fn includes(&self, purpose: NetlistPurpose) -> Result<IncludeBundle> {
        Ok(Default::default())
    }
    /// Returns a database of the standard cell libraries available in the PDK.
    fn standard_cells(&self) -> Result<StdCellDb> {
        Ok(StdCellDb::new())
    }
    /// Returns a database of the available process corners.
    fn corners(&self) -> Result<CornerDb> {
        Ok(CornerDb::new())
    }
}
```

The `layers` function returns a layer database, which includes information on GDS layer numbers, layer purposes, and additional metadata (eg. identifying which metal/via layers and providing layer names).
The `standard_cells` provides zero or more standard cell libraries. The standard cell API is described further in TODO.
The `corners` function provides zero or more process corners. Depending on the corner the user selects, the PDK can include a different set of model libraries.
The `mos_schematic` and `mos_layout` functions instantiate PDK-specific CMOS devices in schematic and layout mode, respectively.
For further information on the other functions available, see the Substrate documentation.

Since PDKs are simply libraries, they are free to provide functions other than the ones specified here.
For instance, a PDK may export a component for a unit capacitor, even though Substrate currently does not
have a unified API for creating capacitors.

== Schematic Entry

A very simple schematic generator, which produces an ideal resistive voltage divider, is shown below:

```rs
impl Component for VDivider {
    // ...
    
  fn schematic(&self, ctx: &mut SchematicCtx) -> Result<()> {
      let out = ctx.port("out", Direction::Output);
      let vdd = ctx.port("vdd", Direction::InOut);
      let vss = ctx.port("vss", Direction::InOut);

      ctx.instantiate::<Resistor>(&SiValue::new(2, SiPrefix::Kilo))?
          .with_connections([("p", vdd), ("n", out)])
          .named("R1")
          .add_to(ctx);

      ctx.instantiate::<Resistor>(&SiValue::new(1, SiPrefix::Kilo))?
          .with_connections([("p", out), ("n", vss)])
          .named("R2")
          .add_to(ctx);
      Ok(())
  }
}
```

This starts by declaring three ports: `out`, `vdd`, and `vss`, with the specified directions.
We then instantiate 2 resistors: one with value $2 k ohm$, and one with value $1 k ohm$,
and connect them appropriately.

This schematic can easily be exported to a SPICE netlist:
```rs
ctx.write_schematic_to_file::<VDivider>(&NoParams, path);
```

Netlist generation in Substrate involves several passes:
+ Netlists are preprocessed to resolve duplicate net, instance, or module names.
+ The netlist is validated for correctness. This currently involves 3 analyses:
  - A name-validity analysis checks for duplicate or SPICE-incompatible names.
  - A netlist connectivity analysis verifies that all modules have their ports connected and that all widths are matched.
  - A net driver analysis verifies that all input ports are driven by at least one source and produces warnings if nets have multiple drivers.
+ A netlisting plugin maps the in-memory representation of Substrate components to simulator specific syntax and writes the content of the netlist to an output stream (usually a file).


== Layout Entry <substrate-layout-entry>

Most analog generators, Substrate included, produce layouts in roughly three steps:
+ Generate or import sub-components.
+ Place sub-components.
+ Route between sub-components.

The first step is described in more detail in @subcomponent-layout-generation, the second step in @placement-utilities, and the third in @routing.

=== Subcomponent Layout Generation <subcomponent-layout-generation>

This section describes how base-layer components, such as transistors, resistors, and capacitors, can be generated or imported into Substrate.

==== Hard Macros
Hard macros allow users to import arbitrary layouts into Substrate, and use them as if they were regular components. They are useful when you are incorporating externally-provided cells (eg. provided by a foundry or generated by a tool other than Substrate), or where writing generator code would be slower and have little benefit over a hand-drawn layout.

Hard macros can be incorporated into Substrate using the `hard_macro` attribute, which is a Rust procedural macro.

```rs
#[hard_macro(
    name = "sram_sp_cell",
    pdk = "sky130-open",
    path_fn = "path",
    gds_cell_name = "sky130_fd_bd_sram__sram_sp_cell_opt1",
    spice_subckt_name = "sram_sp_cell"
)]
pub struct SpCell;
```

The arguments to the procedural macro allow the user to specify a path function. The path function accepts a single argument – a view type (ie. schematic or layout) - and returns the path at which the appropriate view is stored (ie. a SPICE netlist or a GDS file, respectively).

Hard macros can then be instantiated as regular Substrate components, in both layout and schematic mode:
```rust
ctx.instantiate::<SpCell>(&NoParams);
```

==== Raw Layout Utilities

In the spirit of giving the user complete control over generated layout, Substrate allows users to
specify layouts down to individual polygons. To create layout geometry, users specify a layer
(obtained from the PDK API described in @pdks) and a shape.

There is a rich system of utilities for manipulating rectangular geometry, since rectangles are the
predominant shape in integrated circuit layouts. The Substrate documentation lists the full set of
helpers; an image of one page of the documentation is included here for reference.

#figure(
  image("figures/subgeom.png", width: 100%),
  caption: [
    An example page taken from Substrate's geometry API documentation.
  ],
)

The raw layout system provides utilities for:
- Creating and resizing rectangles.
- Grouping layout elements (such as rectangles and instances of subcomponents).
- Relative placement/alignment of layout elements.
- Rotating/mirroring layout elements and groups of layout elements.
- Calculating bounding boxes.
- Flattening hierarchical layout elements.
- Trimming geometry that lies outside a masking shape.

==== PDK-provided Unit Cells

=== Placement Utilities <placement-utilities>

The basis for all placement utilities in Substrate is the `AlignRect` trait,
which provides functions for rectangular/Manhattan positioning for types
that are translatable and have a bounding box.

Users of the `AlignRect` trait specify an `AlignMode`, a reference bounding box or rectangle,
and a spacing. The implementation of the `AlignRect` trait then performs the computations to place
a new bounding box at the requested position relative to the reference box.

The `AlignMode` trait is shown below.

```rust
pub enum AlignMode {
    Left,
    Right,
    Bottom,
    Top,
    CenterHorizontal,
    CenterVertical,
    ToTheRight,
    ToTheLeft,
    Beneath,
    Above,
}
```

These options generally do what you expect. For example, `AlignMode::Right` aligns the right edges of two boxes,
where as `AlignMode::ToTheRight` aligns one box to the right of another box.
If a spacing is specified, `AlignMode::ToTheRight` aligns the second box to the right of the first box,
while leaving the desired spacing in between.

Although the alignment API can be directly useful,
it is often more convenient to use higher-level abstractions
when describing the layout of regular (eg. gridded) structures.
To this end, Substrate provides a variety of tiling APIs.

Each of Substrate's tiling implementations takes as input one or more tiles,
as well as metadata about how to place those tiles:
- The `ArrayTiler` takes a list of tiles, and places them in a vertical or horizontal line.
- The `GridTiler` takes a 2D array of tiles, and places them in a grid.
- The nine patch tiler `NpTiler` takes 9 tiles, and two numbers, $n_x$ and $n_y$.
  It tiles these 9 tiles in a manner similar to nine patch images.
  The center tile is repeated in an $n_x times n_y$ grid.
  The top and bottom edge tiles are repeated in an $n_x times 1$ array
  directly above and below the center tile grid, respectively.
  The left and right edge tiles are similarly placed in an $n_y times 1$ array.
  The corner tiles are placed, unrepeated, at the corners of the center tile grid.

Each of these tilers uses the raw alignment API to position tiles.

To ensure that the tiling APIs are composable, the tilers have few requirements
on what can constitute a tile: anything can be tiled, as long as it can be drawn
into a Substrate layout, and it has a bounding box.

This flexibility makes it easy to add new tile types – to mark a type as tileable,
it just needs to be marked with the `CustomTile` trait (which in turn requires
the type to be drawable and have a bounding box). Indeed, Substrate uses
this flexibility internally to provide custom tile types of its own.

For example, it is common to tile objects according to their bounding box
on a specific layer (rather than their overall bounding box).
Tiling standard cells is a common example in which this problem arises.
In Substrate, supporting layer-specific bounding box tiling requires no changes
to the tiler implementation at all.
Instead, Substrate provides the `LayerBbox` tile type, which implements the
aforementioned `CustomTile` trait. The `LayerBbox` constructor takes an inner tile
(eg. a standard cell layout) and a layer identifier, and exposes a standard tile API to the tiler:
- Drawing a `LayerBbox` tile simply results in drawing the inner tile.
- When calculating the bounding box, `LayerBbox` filters the elements of the inner tile, considering
  only the elements on its selected layer.

Similarly, there is a `Pad` tile type, which adds padding to an inner tile as follows:
- Drawing the `Pad` tile simply draws the inner tile.
- The bounding box of the `Pad` tile is the bounding box of the inner tile, expanded by the width of the padding.

These custom types are easily composable. For example, you can create a `Pad` tile that wraps a `LayerBbox` tile
that in turn wraps a "regular" tile.


=== Routing <routing>

There are three levels of routing abstraction in Substrate:
1. The lowest level of abstraction deals with routing tracks. This layer provides utilities for calculating
   track locations, locating tracks near a point, and creating half tracks
   (tracks that are half the width of a normal track, with the expectation that two half tracks will abut
   to form a full-size track).
2. The second level of abstraction handles manual routing. This layer is intended for situations in which
   routing performance is important and the rough shape of the route is known in advance. One such situation is
   routing the output of a standard cell inverter to the input of an adjacent inverter. This layer
   provides methods for creating elbow jogs, S-shaped jogs, and collections of multiple parallel jogs.
3. The third and highest level of abstraction is fully automatic gridded routing. Users define a routing grid,
   then request that the router draw routes. Each routing request contains a source location and layer,
   a destination location and layer, and a net name string. Reusing a net name across multiple routing requests
   enables the router to reuse routes previously drawn on that net. The algorithm currently used for routing
   is essentially breadth-first search; the router does not attempt to find globally optimal routes.

Further examples of the routing APIs are given later in this thesis, in the context of SRAM22.


Tiling
Hard macros
Logic path delay optimizer


Hammer integration

Standard cells

== Design and Verification Utilities

Spectre/ngspice/calibre integration.

= SRAM 22

SRAM22 is an open-source SRAM generator for the Skywater 130nm open-source process.
SRAM22 programatically generates SRAM blocks by consuming:
+ A TOML configuration file, such as the one shown below.
+ A set of hard macros, including standard cells, a sense amplifier, and SRAM bitcells.
+ A summary of process design rules.
+ A Substrate PDK, which provides a parametric transistor generator.

SRAM22 does not attempt to be process-portable, even though many of the above components
can, in principle, be swapped out to port SRAM22 to a new process.

An example TOML configuration file is shown below:

```toml
num_words = 32
data_width = 32
mux_ratio = 2
write_size = 32
control = "ReplicaV1"
pex_level = "rcc"
```

These options configure the width/depth of the SRAM, the column muxing ratio, and the write mask granularity.
Since running PEX can often take hours or even days, the `pex_level` option allows users to specify
the level of accuracy desired.

An invocation of SRAM22 produces all collateral required for integrating SRAM into a digital flow, including:
- A SPICE netlist.
- A GDS layout.
- A LEF file, identifying pin and blockage locations.
- A Liberty file, specifying timing constraints.
- A Verilog behavioral model.

Users can also request that SRAM22 run checks on the generated SRAM block, including:
- Running LVS.
- Running DRC.
- Running a sanity-check transistor-level functional simulation.

The complete source code for SRAM22 is available on #link("https://github.com/rahulk29/sram22")[GitHub].

@sram-architecture describes the architecture of the generated SRAM blocks.
@layout-generation describes the how SRAM22 programatically generates layout.

== Architecture <sram-architecture>

SRAM22 generates self-timed SRAMs. The internally generated sense amplifier clock is derived
from a replica bitline. Details on the design of the replica timing mechanism can be found in @replica-bitline.

=== Replica Bitline <replica-bitline>

The purpose of the replica bitline is to accurately track the discharge delay of the true bitlines across
process, voltage, and temperature variations. Since SRAM cells are composed of special transistors
not ordinarily used in logic cells, timing mechanisms based on logic (such as inverter chains) do not
track the true bitlines well.

To minimize power consumption due to charging and discharging the bitlines,
the replica delay can be designed to fire the sense amplifiers when just enough voltage difference
has accumulated. This minimum voltage depends primarily on the sensitivity and offset voltage of the
sense amplifiers.

We use a design in which there are $N$ replica columns, each of which is smaller than a regular column by a factor of $K$. In other words, if a regular SRAM column has $h$ cells, each replica column will have $h/K$ cells.
The $N$ replica columns are connected in parallel to reduce timing variation due to random effects in active replica cells.
An inverter senses the discharging replica bitline and fires sense amplifiers.

We now present a method for selecting the values of $N$ and $K$.

We assume that the following values are known (eg. extracted from simulation) and constant:
- The bitline capacitance $C_("bl")$
- The nominal SRAM cell on current, $I_("cell,0")$
- The standard deviation of SRAM cell current, $sigma_(I_("cell"))$
- The standard deviation of the sense amplifier offset voltage $V_("os")$
- The threshold $V_("flip")$ at which an inverter output flips from low to high
- The supply voltage $V_("DD")$

A read error occurs if the sense amps fire before sufficient voltage difference develops on the true bitlines.

For this analysis, we suppose that we must tolerate up to $M_1$ standard deviations of sense amp offset voltage
and $M_2$ standard deviations of SRAM cell current.

The total bitline capacitance of the replica columns is $ C_("replica") = N/K C_("bl"). $
If this capacitance is discharged by a current $I_("replica")$, the time at which the sense amps are enabled is
$ T_("SAE") = C_("replica")/I_("replica")(V_("DD") - V_("flip")). $
Note that nominally $I_("replica") = N I_("cell")$, since the replica column contains $N$ replica cells in parallel.

For a correct read, the voltage difference at the input of the sense amps must be larger than $M_1 V_("os").$
If the true bitlines are discharged by a current $I_("cell")$, we must have
$ T_("SAE") > C_("bl")/I_("cell") M_1 V_("os"). $

The worst case conditions occur when:
- The cell being read is slow: $ I_("cell") = I_("cell,0") - M_2 sigma_(I_("cell")). $

- The replica cells are fast: $ I_("replica") = N I_("cell") + M_2 sqrt(N) sigma_(I_("cell")). $

- The sense amplifiers have a large offset voltage.

We now derive a condition for correctness under the worst case conditions.

The worst case (earliest) time at which the sense amps are fired is

$ T_("SAE") = C_("replica")/I_("replica") (V_("DD") - V_("flip")) = N C_("bl")  (V_("DD") - V_("flip")) / (K (N I_("cell,0") + M_2 sqrt(N) sigma_(I_("cell")))). $ <tsae-max>

The worst case (latest) time at which sufficient bitline voltage margin has accumulated is

$ T_("min") = M_1 C_("bl") V_("os") / (I_("cell") - M_2 sigma_(I_("cell"))). $ <tmin>

For correct operation, @tsae-max must be larger than @tmin. Thus, the correctness constraint is

$ (C_("bl")  (V_("DD") - V_("flip"))) / (K (I_("cell,0") + M_2 1/sqrt(N) sigma_(I_("cell")))) >
(M_1 C_("bl") V_("os")) / (I_("cell") - M_2 sigma_(I_("cell"))). $ <sae-correctness>

@sae-correctness shows that increasing $N$ mitigates the variance of the replica cells,
though it does nothing to alleviate the variance of the SRAM cells.

A simple heuristic to select $N$ and $K$ is to solve for $K$ based on the nominal cell current and worst case
sense amp offset voltage:

$ (C_("bl") (V_("DD") - V_("flip")) / (K I_("cell,0")) = (C_("bl") M_1 V_("os")) / I_("cell,0") $
$ => K = (V_("DD") - V_("flip")) / (M V_("os")).$

The value of $N$ is then determined by finding the minimumm value of $N$ that satisfies @sae-correctness.
Since $N$ does nothing for the SRAM cell current variation, this approach may not always yield a positive solution for $N$.
Such cases can be solved iteratively by decreasing $K$ and then searching for an $N$ satisfying @sae-correctness.


== Layout Generation <layout-generation>

SRAM22 exercises many of the layout APIs described in @substrate-layout-entry.
This section describes a few representative examples.

=== Bitcell Array

SRAM22 uses many of the tiling APIs described in @placement-utilities.
As an example, consider the (toy) 8x8 bitcell array shown in @bitcell8x8.

#figure(
  image("figures/bitcell8x8.png", width: 100%),
  caption: [
    An 8x8 SRAM bitcell array tiled using Substrate.
  ],
) <bitcell8x8>

The bitcell array has several features commonly found in SRAM bitcell arrays:
- One horizontal tap row for every 8 rows of cells.
- One vertical tap column for every 4 columns of cells. Note that this array was
  generated for a column mux ratio of 4. For a column mux ratio of 8, the tap columns
  would be placed every 8 cells.
- Special row end, column end, and corner cells.
- Each SRAM bitcell shares bitline and power contacts with its neighbors.
  As a result, each cell in a row is reflected horizontally with respect to the cell preceeding it.
  Similarly, each cell in a column is reflected vertically with respect to the cell above it.

The requirements for special edge and corner cells makes this a natural fit for a ninepatch tiler.
  

=== Precharge

=== Control Logic

== Architecture
== Layout

= UCIe PHY
== Serializer
== Segmented Driver
= Conclusion
