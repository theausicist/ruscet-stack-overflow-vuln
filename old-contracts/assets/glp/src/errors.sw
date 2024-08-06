// SPDX-License-Identifier: Apache-2.0
library;

pub enum Error {
    GLPAlreadyInitialized: (),
    GLPForbidden: (),
    GLPOnlyMinter: (),

    GLPMintToZeroAccount: (),
    GLPBurnFromZeroAccount: (),
    GLPTransferFromZeroAccount: (),
    GLPTransferToZeroAccount: (),
    GLPApproveFromZeroAccount: (),
    GLPApproveToZeroAccount: (),

    GLPInvalidBurnAssetForwarded: (),
    GLPInvalidBurnAmountForwarded: (),

    GLPInsufficientAllowance: (),
    GLPInsufficientBalance: (),
    GLPBurnAmountExceedsBalance: (),

    GLPInsufficientTransferAmountForwarded: ()
}