"""Main automation script for DM Funnel generation."""
import logging
from datetime import datetime
from utils import (
    load_config,
    get_google_sheets_service,
    get_pending_briefs,
    send_to_slack,
    save_to_google_docs,
    update_google_sheet_status
)
from chains import generate_dm_funnel_variants

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


def process_brief(brief: dict, config: dict, sheets_service) -> bool:
    """Process a single client brief."""
    try:
        logger.info(f"🚀 Processing: {brief['client_name']}")
        
        # Generate variants
        variants = generate_dm_funnel_variants(brief, config)
        
        # Send parent message to Slack
        parent_msg = (
            f"*📋 New DM Funnel: {brief['client_name']}*\n"
            f"*Offer:* {brief['offer_title']}\n"
            f"*Type:* {brief['offer_type']}\n"
            f"*Target:* {brief['target_audience']}\n"
            f"*CTA:* {brief['cta']}\n\n"
            f"_3 variants below in thread_ 👇"
        )
        parent_ts = send_to_slack(parent_msg, brief, config)
        
        # Combine all content for Docs
        all_content = (
            f"DM FUNNEL VARIANTS - {brief['client_name']}\n"
            f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M')}\n"
            f"{'='*50}\n\n"
        )
        
        # Send each variant
        for variant_name, content in variants.items():
            header = f"*🎯 {variant_name.replace('_', ' ').title()}*\n"
            send_to_slack(header + content, brief, config, thread_ts=parent_ts)
            all_content += f"{header}\n{content}\n{'-'*40}\n\n"
        
        # Save to Google Docs
        save_to_google_docs(all_content, brief, config)
        
        # Update status
        update_google_sheet_status(sheets_service, config, brief["row_index"])
        
        logger.info(f"✅ Done: {brief['client_name']}")
        return True
    
    except Exception as e:
        logger.error(f"❌ Failed: {brief['client_name']}: {e}")
        try:
            update_google_sheet_status(sheets_service, config, brief["row_index"], "error")
        except:
            pass
        return False


def main():
    """Main pipeline."""
    logger.info("="*60)
    logger.info("DM FUNNEL AUTOMATION STARTING")
    logger.info("="*60)
    
    config = load_config()
    sheets_service = get_google_sheets_service(config)
    briefs = get_pending_briefs(sheets_service, config)
    
    if not briefs:
        logger.info("No pending briefs found.")
        return
    
    logger.info(f"Processing {len(briefs)} brief(s)...")
    
    success = 0
    for i, brief in enumerate(briefs, 1):
        logger.info(f"\n📝 {i}/{len(briefs)}")
        if process_brief(brief, config, sheets_service):
            success += 1
    
    logger.info(f"\n{'='*60}")
    logger.info(f"COMPLETE: {success}/{len(briefs)} successful")
    logger.info("="*60)


if __name__ == "__main__":
    main()
