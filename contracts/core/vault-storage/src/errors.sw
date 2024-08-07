// SPDX-License-Identifier: Apache-2.0
library;

pub enum Error {
    VaultStorageForbiddenNotGov: (),
    VaultStorageOnlyAuthorizedEntity: (),
    
    VaultStorageAlreadyInitialized: (),
    VaultStorageInvalidUSDGAsset: (),
    VaultStorageZeroAsset: (),

    VaultStorageMaxUsdgExceeded: (),
    
    VaultStorageInvalidTaxBasisPoints: (),
    VaultStorageInvalidStableTaxBasisPoints: (),
    VaultStorageInvalidMintBurnFeeBasisPoints: (),
    VaultStorageInvalidSwapFeeBasisPoints: (),
    VaultStorageInvalidStableSwapFeeBasisPoints: (),
    VaultStorageInvalidMarginFeeBasisPoints: (),
    VaultStorageInvalidLiquidationFeeUsd: (),

    VaultStorageInvalidFundingInterval: (),
    VaultStorageInvalidFundingRateFactor: (),
    VaultStorageInvalidStableFundingRateFactor: (),

    VaultStorageAssetNotWhitelisted: (),
}