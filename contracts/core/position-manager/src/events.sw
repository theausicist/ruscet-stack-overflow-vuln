// SPDX-License-Identifier: Apache-2.0
library;

use helpers::{
    context::*,
};

pub struct SetOrderKeeper {
    pub account: Account,
    pub is_active: bool,
}

pub struct SetLiquidator {
    pub account: Account,
    pub is_active: bool,
}

pub struct SetPartner {
    pub account: Account,
    pub is_active: bool,
}

pub struct SetInLegacyMode {
    pub in_legacy_mode: bool,
}

pub struct SetShouldValidatorIncreaseOrder {
    pub should_validator_increase_order: bool,
}