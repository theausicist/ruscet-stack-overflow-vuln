// SPDX-License-Identifier: Apache-2.0
library;

pub enum Error {
    BPMAlreadyInitialized: (),

    BPMVaultStorageZero: (),
    BPMRouterZero: (),
    BPMShortsTrackerZero: (),
    
    BPMForbidden: (),
    BPMOnlyChildContract: (),
    BPMIncorrectLength: (),
    BPMIncorrectPathLength: (),

    BPMMaxLongsExceeded: (),
    BPMMaxShortsExceeded: (),

    BPMMarkPriceGtPrice: (),
    BPMMarkPriceLtPrice: (),

    BPMInvalidAssetForwarded: (),
    BPMInvalidAssetAmountForwardedToCoverFeeAmount: (),
}