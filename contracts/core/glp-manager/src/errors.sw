// SPDX-License-Identifier: Apache-2.0
library;

pub enum Error {
    GLPManagerAlreadyInitialized: (),
    GLPManagerForbidden: (),
    GLPManagerOnlyHandler: (),

    GLPManagerHandlerZero: (),

    GLPManagerInvalidCooldownDuration: (),
    GLPManagerForbiddenInPrivateMode: (),

    GLPManagerInvalidWeight: (),

    GLPManagerInvalidAmount: (),
    GLPManagerInvalidAssetForwarded: (),
    GLPManagerInvalidAssetAmountForwarded: (),
    GLPManagerInsufficientUSDGOutput: (),
    GLPManagerInsufficientGLPOutput: (),

    GLPManagerCooldownDurationNotYetPassed: (),
    GLPManagerInvalidGlpAmount: (),
    GLPManagerInsufficientOutput: (),
}