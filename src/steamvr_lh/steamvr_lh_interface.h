// Copyright 2023, Shawn Wallace
// SPDX-License-Identifier: BSL-1.0
/*!
 * @file
 * @brief SteamVR driver device interface.
 * @author Shawn Wallace <yungwallace@live.com>
 * @ingroup drv_steamvr_lh
 */

#include <xrt/xrt_results.h>

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/*!
 * @defgroup drv_steamvr_lh Wrapper for the SteamVR Lighthouse driver.
 * @ingroup drv
 *
 * @brief Wrapper driver around the SteamVR Lighthouse driver.
 */

/*!
 * @dir drivers/steamvr_lh
 *
 * @brief @ref drv_steamvr_lh files.
 */

/*!
 * Creates the steamvr system devices.
 *
 * @ingroup drv_steamvr_lh
 */
enum xrt_result
steamvr_lh_create_devices(struct xrt_prober *xp, struct xrt_system_devices **out_xsysd);

/*!
 * Give the steamvr_lh host context references to the real headset and
 * controllers, so hosted drivers (SlimeVR, Standable, ...) can read their
 * poses through IVRServerDriverHost::GetRawTrackedDevicePoses.
 *
 * @ingroup drv_steamvr_lh
 */
void
steamvr_lh_set_feeder_devices(struct xrt_device *head,
                              struct xrt_device *left,
                              struct xrt_device *right);


#ifdef __cplusplus
}
#endif
