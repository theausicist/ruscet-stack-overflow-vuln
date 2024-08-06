// SPDX-License-Identifier: Apache-2.0
contract;

mod errors;
use std::auth::msg_sender;
use ::errors::*;

//// CALLEE /////
abi Callee {
	fn get_sender() -> (bool, bool);

	#[storage(read, write)]
	fn call_me_fail();
}

impl Callee for Contract {
	fn get_sender() -> (bool, bool) { (false, false) }

	#[storage(read, write)]
	fn call_me_fail() {}
}
//// CALLEE /////

abi Caller {
	fn call_callee(contract_id: ContractId) -> (bool, bool);

	#[storage(read, write)]
	fn call_callee_that_fails(contr_id: ContractId);
}

storage {
	six: u64 = 6
}
 
impl Caller for Contract {
	// (address, contract)
	fn call_callee(contr_id: ContractId) -> (bool, bool) {
		let callee = abi(Callee, contr_id.into());

		callee.get_sender()
	}

	#[storage(read, write)]
	fn call_callee_that_fails(contr_id: ContractId) {
		let callee = abi(Callee, contr_id.into());

		require(
			storage.six.read() == 6,
			Error::CallerError9
		);

		callee.call_me_fail();

		require(
			storage.six.read() != 6,
			Error::CallerError9
		);
	}
}
