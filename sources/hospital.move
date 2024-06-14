module Hospital::hospital {
    use std::string::{Self,String};
    use sui::coin::{Self, Coin};
    use sui::sui::{SUI};
    use sui::balance::{Self, Balance};
    use sui::clock::{Clock, timestamp_ms};
    use sui::table::{Self, Table};

    // ERROR CODES
    const TREATMENT_HAVE_COMPLETE: u64 = 1;
    const TREATMENT_PRICE_HAVE_SET: u64 = 2;
    const TREATMENT_PRICE_NOT_SET: u64 = 3;
    const ERROR_INSUFFICIENT_FUNDS: u64 = 4;
    const DOCTOR_NOTIN_HOSPITAL: u64 = 5;
    const PHARMACIST_NOTIN_HOSPITAL: u64 = 6;
    const TIME_OUT: u64 = 7;
    const TREATMENT_NOT_BELONG_TO_YOU: u64 = 8;
    const INVALID_DATA: u64 = 9;
    const UNAUTHORIZED_ACCESS: u64 = 10;

    // CONSTANTS
    const ZERO_ADDRESS: address = @0x0;
    const ONE_DAY: u64 = 86400;

    // Structs
    public struct Treatment has key, store {
        id: UID,
        key: address,
        doctor_address: address,
        pharmacist_address: address,
        payer_address: address,
        patient_information: String,
        condition_description: String,
        prescribe_medicine: String,
        medication_guide: String,
        date: u64,
        price: u64,
        complete: bool,
        status: String,
        timeout: u64
    }

    public struct Hospital has key, store {
        id: UID,
        hospital_address: address,
        name: String,
        balance: Balance<SUI>
    }

    public struct Patient has key, store {
        id: UID,
        treatments: Table<address, Treatment>,
        patient_address: address,
        balance: Balance<SUI>
    }

    public struct AdminCap has key {
        id: UID
    }

    public struct DoctorCap has key {
        id: UID,
        hospital: address
    }

    public struct PharmacistCap has key {
        id: UID,
        hospital: address
    }

    public struct Roles has key, store {
        id:UID,
        admin: address,
        hospitals: vector<address>,
        doctors: vector<address>,
        pharmacists: vector<address>,
        patients: vector<address>
    }
    // Initialize admin capabilities
    fun init(ctx: &mut TxContext) {
        let admin_address = ctx.sender();
        let roles= Roles {
            id:object::new(ctx),
            admin:admin_address,
            hospitals: vector::empty(),
            doctors: vector::empty(),
            pharmacists: vector::empty(),
            patients: vector::empty(),
        };
        transfer::public_share_object(roles);
    }

    // Add a new hospital
    public fun add_hospital(roles: &mut Roles, new_hospital: address, ctx: &mut TxContext) {
        assert!(roles.admin==ctx.sender(), UNAUTHORIZED_ACCESS);
        vector::push_back(&mut roles.hospitals, new_hospital);
    }

    // The administrator grants permission to the doctor
    public fun approve_doctor_cap(roles: &mut Roles, hospital: &Hospital, to: address, ctx: &mut TxContext) {
        assert!(roles.admin==ctx.sender(), UNAUTHORIZED_ACCESS);
        vector::push_back(&mut roles.doctors, to);
        let doctor_cap = DoctorCap {
            id: object::new(ctx),
            hospital: hospital.hospital_address
        };
        transfer::transfer(doctor_cap, to);
    }

    // The administrator grants permissions to the pharmacist
    public fun approve_pharmacist_cap(roles: &mut Roles, hospital: &Hospital, to: address, ctx: &mut TxContext) {
        assert!(roles.admin==ctx.sender(), UNAUTHORIZED_ACCESS);
        vector::push_back(&mut roles.pharmacists, to);
        let pharmacist_cap = PharmacistCap {
            id: object::new(ctx),
            hospital: hospital.hospital_address
        };
        transfer::transfer(pharmacist_cap, to);
    }

    // The administrator creates a hospital object
    public fun create_hospital(roles: &mut Roles, hospital_name: String, ctx: &mut TxContext) {
        assert!(roles.admin==ctx.sender(), UNAUTHORIZED_ACCESS);
        
        let id_ = object::new(ctx);
        let hospital_address_ = object::uid_to_address(&id_);
        let hospital = Hospital {
            id: id_,
            hospital_address: hospital_address_,
            name: hospital_name,
            balance: balance::zero()
        };
        transfer::public_share_object(hospital);
        add_hospital(roles, hospital_address_, ctx);
    }

    // The doctor creates a medical treatment
    public fun create_treatment(doctor_cap: &DoctorCap, hospital: &Hospital, patient_information: String, condition_description: String, prescribe_medicine: String, medication_guide: String, clock: &Clock, ctx: &mut TxContext) {
        assert!(doctor_cap.hospital == hospital.hospital_address, DOCTOR_NOTIN_HOSPITAL);
    
        let id_ = object::new(ctx);
        let key_ = object::uid_to_address(&id_);
        let treatment = Treatment {
            id: id_,
            key: key_,
            doctor_address: ctx.sender(),
            pharmacist_address: ZERO_ADDRESS,
            payer_address: ZERO_ADDRESS,
            patient_information: patient_information,
            condition_description: condition_description,
            prescribe_medicine: prescribe_medicine,
            medication_guide: medication_guide,
            date: timestamp_ms(clock),
            price: 0,
            complete: false,
            status: string::utf8(b"Pending"),
            timeout: ONE_DAY
        };
        transfer::share_object(treatment);
    }

    // The patient creates a patient object
    public fun new_patient( ctx: &mut TxContext) {
        let patient = Patient {
            id: object::new(ctx),
            treatments: table::new(ctx),
            patient_address: ctx.sender(),
            balance: balance::zero()
        };
        transfer::public_transfer(patient, ctx.sender());
    }

    // The pharmacist determines the price of the medicine
    public fun set_price(pharmacist_cap: &PharmacistCap, hospital: &Hospital, treatment: &mut Treatment, price: u64, clock: &Clock, ctx: &mut TxContext) {
        assert!(pharmacist_cap.hospital == hospital.hospital_address, PHARMACIST_NOTIN_HOSPITAL);
        assert!(!treatment.complete, TREATMENT_HAVE_COMPLETE);
        assert!(treatment.price == 0, TREATMENT_PRICE_HAVE_SET);
        assert!(treatment.date + treatment.timeout > timestamp_ms(clock), TIME_OUT);
        treatment.pharmacist_address = ctx.sender();
        treatment.price = price;
        treatment.status = string::utf8(b"Priced");
    }

    // The patient pays the amount
    public fun pay_money(hospital: &mut Hospital, treatment: &mut Treatment, patient: &mut Patient, clock: &Clock, ctx: &mut TxContext) {
        assert!(treatment.payer_address == patient.patient_address, TREATMENT_NOT_BELONG_TO_YOU);
        assert!(!treatment.complete, TREATMENT_HAVE_COMPLETE);
        assert!(treatment.date + treatment.timeout > timestamp_ms(clock), TIME_OUT);
        assert!(treatment.price != 0, TREATMENT_PRICE_NOT_SET);
        assert!(balance::value<SUI>(&patient.balance) >= treatment.price, ERROR_INSUFFICIENT_FUNDS);
        let pay_balance = balance::split<SUI>(&mut patient.balance, treatment.price);
        balance::join(&mut hospital.balance, pay_balance);
        treatment.payer_address = ctx.sender();
        treatment.complete = true;
        treatment.status =  string::utf8(b"Paid");
    }
    // Add treatment to patient's history
    public fun add_treatment(treatment: Treatment, patient: &mut Patient) {
        table::add(&mut patient.treatments, treatment.key, treatment);
    }

    // The patient deposits money into the patient account
    public fun patient_deposit(patient: &mut Patient, coin: Coin<SUI>) {
        coin::put(&mut patient.balance, coin);
    }

    // The patient withdraws money from the patient account
    public fun patient_withdraw(patient: &mut Patient, ctx: &mut TxContext) {
        let balance_ = balance::withdraw_all(&mut patient.balance);
        let coin_ = coin::from_balance(balance_, ctx);
        transfer::public_transfer(coin_, ctx.sender());
    }

    // The administrator withdraws the hospital's money and transfers it to a specified address
    public fun hospital_withdraw(_: &AdminCap, hospital: &mut Hospital, to: address, ctx: &mut TxContext) {
        let balance_ = balance::withdraw_all(&mut hospital.balance);
        let coin_ = coin::from_balance(balance_, ctx);
        transfer::public_transfer(coin_, to);
    }

    // Utility functions
    public fun patient_balance(patient: &Patient): u64 {
        balance::value(&patient.balance)
    }

    public fun hospital_balance(hospital: &Hospital): u64 {
        balance::value(&hospital.balance)
    }

    public fun treatment_price(treatment: &Treatment): u64 {
        treatment.price
    }

    // Retrieve specific treatment details
    public fun get_treatment(patient: &Patient, treatment_id: address): &Treatment {
        table::borrow(&patient.treatments, treatment_id)
    }

    // Set configurable timeout for treatments
    public fun set_treatment_timeout(_: &DoctorCap, treatment: &mut Treatment, timeout: u64, ctx: &mut TxContext) {
        assert!(treatment.doctor_address ==ctx.sender() , UNAUTHORIZED_ACCESS);
        treatment.timeout = timeout;
    }
}
