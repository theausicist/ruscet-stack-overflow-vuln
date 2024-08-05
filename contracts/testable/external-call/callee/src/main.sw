// SPDX-License-Identifier: Apache-2.0
contract;

use std::{
    auth::msg_sender,
    block::timestamp,
    call_frames::{
        contract_id,
        msg_asset_id,
    },
    constants::BASE_ASSET_ID,
    context::*,
	identity::Identity,
    revert::require,
    asset::{
        force_transfer_to_contract,
        mint_to_address,
        transfer_to_address,
    },
};
use helpers::utils::get_sender;

abi Callee {
	fn get_sender() -> (bool, bool);
}

impl Callee for Contract {
	fn get_sender() -> (bool, bool) {
		let sender = get_sender();

		if !sender.is_contract {
			(true, false)
		} else {
			(false, true)
		}
	}
}