// SPDX-License-Identifier: Apache-2.0
library;

pub enum Error {
    FungibleFactoryAlreadyInitialized: (),
    FungibleFactoryNameAlreadySet: (),
    FungibleFactorySymbolAlreadySet: (),
    FungibleFactoryDecimalsAlreadySet: (),

    FungibleFactoryBurnInsufficientAssetForwarded: (),
    FungibleFactoryBurnInsufficientAmountForwarded: (),

    FungibleFactoryInsufficientAssetForwarded: (),
    FungibleFactoryInsufficientAmountForwarded: (),
}
