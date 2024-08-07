// SPDX-License-Identifier: Apache-2.0
library;

pub enum Error {
    GMXAlreadyInitialized: (),
    GMXForbidden: (),
    GMXOnlyMinter: (),

    GMXMintToZeroAccount: (),
    GMXBurnFromZeroAccount: (),
    GMXTransferFromZeroAccount: (),
    GMXTransferToZeroAccount: (),
    GMXApproveFromZeroAccount: (),
    GMXApproveToZeroAccount: (),

    GMXInvalidBurnAssetForwarded: (),
    GMXInvalidBurnAmountForwarded: (),

    GMXInsufficientAllowance: (),
    GMXInsufficientBalance: (),
    GMXBurnAmountExceedsBalance: (),

    GMXInsufficientTransferAmountForwarded: ()
}