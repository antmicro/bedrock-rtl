// SPDX-License-Identifier: Apache-2.0

package br_amba_atb_funnel_sim_pkg;

  // Source modes select whether enabled sources begin together or staggered.
  typedef enum int {
    AtbFunnelSourceAligned,
    AtbFunnelSourceStaggered
  } atb_funnel_source_mode_t;

  // Destination-ready patterns are driven by the scenario driver.
  typedef enum int {
    AtbFunnelDstReadyAlways,
    AtbFunnelDstReadyAlternating,
    AtbFunnelDstReadyPeriodicStall
  } atb_funnel_dst_ready_pattern_t;

  localparam int AtbFunnelSourceSeedStride = 16;

endpackage : br_amba_atb_funnel_sim_pkg
