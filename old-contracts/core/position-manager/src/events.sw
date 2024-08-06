// SPDX-License-Identifier: Apache-2.0
library;

pub struct SetOrderKeeper {
    account: Address,
    is_active: bool,
}

pub struct SetLiquidator {
    account: Address,
    is_active: bool,
}

pub struct SetPartner {
    account: Address,
    is_active: bool,
}

pub struct SetInLegacyMode {
    in_legacy_mode: bool,
}

pub struct SetShouldValidatorIncreaseOrder {
    should_validator_increase_order: bool,
}