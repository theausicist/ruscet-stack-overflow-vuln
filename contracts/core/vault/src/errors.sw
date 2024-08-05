// SPDX-License-Identifier: Apache-2.0
library;

pub enum Error {
    VaultAlreadyInitialized: (),
    VaultInvalidUSDGAsset: (),
    VaultForbiddenNotGov: (),
    VaultForbiddenNotManager: (),
    VaultInvalidMsgCaller: (),
    VaultZeroAsset: (),

    VaultMaxUsdgExceeded: (),
    VaultMaxShortsExceeded: (),
    VaultMaxLeverageExceeded: (),
    VaultPoolAmountExceeded: (),
    VaultPositionSizeExceeded: (),
    VaultPositionCollateralExceeded: (),

    VaultReserveExceedsPool: (),
    VaultInvalidIncrease: (),
    VaultInsufficientReserve: (),

    VaultInsufficientCollateralForFees: (),

    VaultInvalidPricePrecision: (),
    VaultInvalidMaxLiquidationFeeUsd: (),

    VaultPriceQueriedIsZero: (),

    VaultPoolAmountLtBuffer: (),
    VaultCollateralShouldBeWithdrawn: (),
    VaultSizeMustBeMoreThanCollateral: (),
    
    VaultInvalidTaxBasisPoints: (),
    VaultInvalidStableTaxBasisPoints: (),
    VaultInvalidMintBurnFeeBasisPoints: (),
    VaultInvalidSwapFeeBasisPoints: (),
    VaultInvalidStableSwapFeeBasisPoints: (),
    VaultInvalidMarginFeeBasisPoints: (),
    VaultInvalidLiquidationFeeUsd: (),
    VaultPositionCannotBeLiquidated: (),

    VaultInvalidFundingInterval: (),
    VaultInvalidFundingRateFactor: (),
    VaultInvalidStableFundingRateFactor: (),

    VaultAssetNotWhitelisted: (),
    VaultInvalidAssetAmount: (),
    VaultInvalidUsdgAmount: (),
    VaultInvalidRedemptionAmount: (),

    VaultInvalidPosition: (),
    VaultInvalidAmountIn: (),
    VaultInvalidAmountOut: (),
    VaultInvalidPositionSize: (),
    VaultInvalidAveragePrice: (),
    VaultInvalidLiquidator: (),

    VaultEmptyPosition: (),

    VaultSwapsNotEnabled: (),
    VaultLeverageNotEnabled: (),

    VaultAssetInNotWhitelisted: (),
    VaultAssetOutNotWhitelisted: (),
    VaultAssetsAreEqual: (),
    
    VaultLongCollateralIndexAssetsMismatch: (),
    VaultLongCollateralAssetNotWhitelisted: (),
    VaultLongCollateralAssetMustNotBeStableAsset: (),

    VaultShortCollateralAssetNotWhitelisted: (),
    VaultShortCollateralAssetMustBeStableAsset: (),
    VaultShortIndexAssetMustNotBeStableAsset: (),
    VaultShortIndexAssetNotShortable: (),

    VaultLossesExceedCollateral: (),
    VaultFeesExceedCollateral: (),
    VaultLiquidationFeesExceedCollateral: (),

    VaultInvalidMintAmountGtU64Max: (),
    VaultInvalidUSDGBurnAmountGtU64Max: ()
}