// SPDX-License-Identifier: Apache-2.0
library;

pub enum Error {
    PositionRouterAlreadyInitialized: (),
    PositionRouterForbidden: (),
    PositionRouterExpectedPositionKeeper: (),
    PositionRouterExpectedCallerToBeKeeper: (),
    PositionRouterExpectedCallerToBeAccount: (),

    PositionRouterFeeTooLow: (),
    PositionRouterInvalidPathLen: (),

    PositionRouterDelay: (),
    PositionRouterExpired: (),
}