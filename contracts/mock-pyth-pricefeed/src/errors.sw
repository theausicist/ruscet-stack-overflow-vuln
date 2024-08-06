// SPDX-License-Identifier: Apache-2.0
library;

pub enum Error {
    MockPythPricefeedAlreadyInitialized: (),
    MockPythPricefeedPricefeedInfoNotSet: (),
    
    MockPythPricefeedForbidden: (),

    MockPythPricefeedInvalidUpdateDataLen: (),
    MockPythPricefeedStalePrice: (),

}