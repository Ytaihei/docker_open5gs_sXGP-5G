/*
 * Missing implementation for handle_rrc_con_setup_complete function in srsRAN_4G
 * This should be added to rrc_ue.cc around line 800 after handle_rrc_con_reest_complete
 */

void rrc::ue::handle_rrc_con_setup_complete(asn1::rrc::rrc_conn_setup_complete_s* msg,
                                           srsran::unique_byte_buffer_t pdu)
{
  // Log event
  asn1::json_writer json_writer;
  msg->to_json(json_writer);
  event_logger::get().log_rrc_event(ue_cell_list.get_ue_cc_idx(UE_PCELL_CC_IDX)->cell_common->enb_cc_idx,
                                    asn1::octstring_to_string(last_ul_msg->msg, last_ul_msg->N_bytes),
                                    json_writer.to_string(),
                                    static_cast<unsigned>(rrc_event_type::con_setup_complete),
                                    static_cast<unsigned>(procedure_result_code::none),
                                    rnti);

  parent->logger.info("RRCConnectionSetupComplete transaction ID: %d", msg->rrc_transaction_id);

  // Inform PHY about the configuration completion
  parent->phy->complete_config(rnti);

  // TODO: msg->selected_plmn_id - used to select PLMN from SIB1 list
  // TODO: if(msg->registered_mme_present) - the indicated MME should be used from a pool

  // Signal MAC scheduler that configuration was successful
  mac_ctrl.handle_con_setup_complete();

  // Change state to indicate connection setup is complete
  state = RRC_STATE_WAIT_FOR_SECURITY_MODE_COMPLETE;

  // Extract NAS-PDU from RRCConnectionSetupComplete message
  const auto& setup_complete_r8 = msg->crit_exts.rrc_conn_setup_complete_r8();
  if (setup_complete_r8.ded_info_nas_present) {
    // Create buffer for NAS PDU
    srsran::unique_byte_buffer_t nas_pdu = srsran::make_byte_buffer();
    if (nas_pdu == nullptr) {
      parent->logger.error("Couldn't allocate NAS PDU buffer in %s().", __FUNCTION__);
      return;
    }

    // Copy NAS PDU data
    nas_pdu->N_bytes = setup_complete_r8.ded_info_nas.size();
    if (nas_pdu->N_bytes > nas_pdu->get_tailroom()) {
      parent->logger.error("NAS PDU too large (%d bytes) in %s().", nas_pdu->N_bytes, __FUNCTION__);
      return;
    }
    memcpy(nas_pdu->msg, setup_complete_r8.ded_info_nas.data(), nas_pdu->N_bytes);

    parent->logger.info("Sending InitialUEMessage with NAS PDU (%d bytes) for rnti=0x%x",
                       nas_pdu->N_bytes, rnti);

    // Determine RRC Establishment Cause
    asn1::s1ap::rrc_establishment_cause_e s1ap_cause = asn1::s1ap::rrc_establishment_cause_e::mo_sig;
    switch (establishment_cause) {
      case establishment_cause_opts::emergency:
        s1ap_cause = asn1::s1ap::rrc_establishment_cause_e::emergency;
        break;
      case establishment_cause_opts::high_prio_access:
        s1ap_cause = asn1::s1ap::rrc_establishment_cause_e::high_prio_access;
        break;
      case establishment_cause_opts::mt_access:
        s1ap_cause = asn1::s1ap::rrc_establishment_cause_e::mt_access;
        break;
      case establishment_cause_opts::mo_sig:
      default:
        s1ap_cause = asn1::s1ap::rrc_establishment_cause_e::mo_sig;
        break;
    }

    // Send Initial UE Message to S1AP (which will be converted to Initial UE Message)
    const ue_cell_ded* pcell = ue_cell_list.get_ue_cc_idx(UE_PCELL_CC_IDX);
    if (has_tmsi) {
      parent->s1ap->initial_ue(rnti,
                              pcell->cell_common->enb_cc_idx,
                              s1ap_cause,
                              std::move(nas_pdu),
                              m_tmsi,
                              mmec);
    } else {
      parent->s1ap->initial_ue(rnti,
                              pcell->cell_common->enb_cc_idx,
                              s1ap_cause,
                              std::move(nas_pdu));
    }
  } else {
    parent->logger.warning("RRCConnectionSetupComplete without NAS-PDU for rnti=0x%x", rnti);
  }

  // Set activity timeout for further processing
  set_activity_timeout(UE_INACTIVITY_TIMEOUT);
}
