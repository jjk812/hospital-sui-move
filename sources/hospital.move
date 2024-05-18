module Hospital::hospital {
    use sui::tx_context::{sender};
    use std::string::String;
    use sui::coin::{Self, Coin};
    use sui::sui::{SUI};
    use sui::balance::{Self,Balance};
    use sui::clock::{Clock,timestamp_ms};
    use sui::table::{Self, Table};

    //ERROR
    const TREATMENT_HAVE_COMPLETE:u64=1;
    const TREATMENT_PRICE_HAVE_SET:u64=2;
    const TREATMENT_PRICE_NOT_SET:u64=3;
    const ERROR_INSUFFICIENT_FUNDS:u64=4;
    const DOCTOR_NOTIN_HOSPITAL:u64=5;
    const PHARMACIST_NOTIN_HOSPITAL:u64=6;
    const TIME_OUT:u64=7;
    const TREATMENT_NOT_BELONG_TO_YOU:u64=8;
    const TREATMENT_SHOULD_COMPLETE:u64=9;
    //CONSTANT
    const ZERO_ADDRESS:address=@0x0;
    const ONE_DAY:u64=86400;
    
    public struct Treatment has key,store{
        id: UID,
        key:address,
        doctor_address:address,
        pharmacist_address:address,
        payer_address:address,
        patient_information:String,
        condition_description:String,
        prescribe_medicine:String,
        medication_guide:String,
        data:u64,
        price:u64,
        complete:bool
    }
    public struct Hospital has key,store{
        id:UID,
        hospital_address:address,
        name:String,
        balance:Balance<SUI>
    }
    public struct Patient has key, store {
        id: UID,
        treatments: Table<address, Treatment>,
        patient_address: address,
        balance: Balance<SUI>
    }
    public struct AdminCap has key{
        id: UID
    }
    public struct DoctorCap has key{
        id: UID,
        hospital:address
    }
    public struct PharmacistCap has key{
        id: UID,
        hospital:address
    }
    fun init(ctx:&mut TxContext){
        let admin=AdminCap{
            id:object::new(ctx)
        };
        transfer::transfer(admin,sender(ctx))
    }
   //The administrator grants permission to the doctor.
    public fun approveDoctorCap(_:&AdminCap,hospital:&Hospital,ctx:&mut TxContext,to:address){

        let doctor_cap=DoctorCap{
            id:object::new(ctx),
            hospital:hospital.hospital_address

        };
        transfer::transfer(doctor_cap,to)
    } 
    //The administrator grants permissions to the pharmacist.
    public fun approvePharmacistCap(_:&AdminCap,hospital:&Hospital,ctx:&mut TxContext,to:address){

        let pharmacist_cap=PharmacistCap{
            id:object::new(ctx),
            hospital:hospital.hospital_address
        };
        transfer::transfer(pharmacist_cap,to);
    } 
    //The administrator creates a hospital object.
    public fun create_hospital(_:&AdminCap,ctx:&mut TxContext,hospital_name:String){
        let id_ = object::new(ctx);
        let hospital_address_ = object::uid_to_address(&id_);
        let hospital=Hospital{
            id:id_,
            hospital_address:hospital_address_,
            name:hospital_name,
            balance:balance::zero()
        };
        transfer::public_share_object(hospital);

    }
    //The doctor creates a medical treatment.
    public fun create_treatment(doctor_cap:&DoctorCap,hospital:& Hospital,ctx:&mut TxContext,patient_information:String,condition_description:String,prescribe_medicine:String,medication_guide:String,clock: &Clock){
        assert!(doctor_cap.hospital==hospital.hospital_address,DOCTOR_NOTIN_HOSPITAL);
        let id_ = object::new(ctx);
        let key_ = object::uid_to_address(&id_);
        let treatment = Treatment{
            id:id_,
            key:key_,
            doctor_address:sender(ctx),
            pharmacist_address:ZERO_ADDRESS,
            payer_address:ZERO_ADDRESS,
            patient_information:patient_information,
            condition_description:condition_description,
            prescribe_medicine:prescribe_medicine,
            medication_guide:medication_guide,
            data:timestamp_ms(clock),
            price:0,
            complete:false
        };


        transfer::share_object(treatment);
    }
    //The patient creates a patient object.
    public fun new_patient(ctx:&mut TxContext){
        let patient=Patient{
            id:object::new(ctx),
            treatments: table::new(ctx),
            patient_address:sender(ctx),
            balance:balance::zero()
        };
        transfer::public_transfer(patient,sender(ctx));
    }
    //The pharmacist determines the price of the medicine.
    public fun set_price(ctx:&mut TxContext,pharmacist_cap:&PharmacistCap,hospital:& Hospital,treatment:&mut Treatment,price:u64,clock: &Clock){
        assert!(pharmacist_cap.hospital==hospital.hospital_address,PHARMACIST_NOTIN_HOSPITAL);
        assert!(!treatment.complete, TREATMENT_HAVE_COMPLETE);
        assert!(treatment.price==0, TREATMENT_PRICE_HAVE_SET);
        assert!(treatment.data+ONE_DAY>timestamp_ms(clock),TIME_OUT);
        treatment.pharmacist_address=sender(ctx);
        treatment.price=price;
    }
    //The patient pays the amount.
    public fun pay_money(ctx:&mut TxContext,hospital:&mut Hospital,treatment:&mut Treatment,patient:&mut Patient,clock: &Clock){
        assert!(treatment.payer_address==patient.patient_address,TREATMENT_NOT_BELONG_TO_YOU);
        assert!(!treatment.complete, TREATMENT_HAVE_COMPLETE);
        assert!(treatment.data+ONE_DAY>timestamp_ms(clock),TIME_OUT);
        assert!(!(treatment.price==0), TREATMENT_PRICE_NOT_SET);
        assert!(balance::value<SUI>(&patient.balance) >= treatment.price, ERROR_INSUFFICIENT_FUNDS);
        let pay_balance = balance::split<SUI>(&mut patient.balance,treatment.price);
        balance::join(&mut hospital.balance, pay_balance);
        treatment.payer_address=sender(ctx);
        treatment.complete=true;

    }
    public fun addtreatment(treatment:Treatment,patient:&mut Patient){
        assert!(treatment.complete,TREATMENT_SHOULD_COMPLETE);
        assert!(treatment.payer_address==patient.patient_address,TREATMENT_NOT_BELONG_TO_YOU);
        table::add(&mut patient.treatments,treatment.key, treatment);
    }
    //The patient deposits money into the patient account.
    public fun patient_deposit(patient:&mut Patient,coin:Coin<SUI>){
        coin::put(&mut patient.balance, coin);
    }
    //The patient withdraws money from the patient account.
    public fun patient_withdraw(ctx:&mut TxContext,patient:&mut Patient){
        let balance_ = balance::withdraw_all(&mut patient.balance);
        let coin_ = coin::from_balance(balance_,ctx);
        transfer::public_transfer(coin_,sender(ctx));
        
    }
    //The administrator withdraws the hospital's money and transfers it to a specified address.
    public fun hospital_withdraw(_:&AdminCap,ctx:&mut TxContext,hospital:&mut Hospital,to:address){
        let balance_ = balance::withdraw_all(&mut hospital.balance);
        let coin_ = coin::from_balance(balance_,ctx);
        transfer::public_transfer(coin_,to);
    }
    public fun patient_balance(patient:& Patient):u64{
        balance::value(&patient.balance)
    }
    public fun hospital_balance(hospital:& Hospital):u64{
        balance::value(&hospital.balance)
    }
    public fun treatment_price(treatment:& Treatment):u64{
        treatment.price
    }
}
