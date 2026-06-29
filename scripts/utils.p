"""Utility functions for Google Sheets, Slack, and Google Docs."""
import yaml
import logging
from typing import Dict, List
from google.oauth2 import service_account
from googleapiclient.discovery import build
from slack_sdk import WebClient
from slack_sdk.errors import SlackApiError

logger = logging.getLogger(__name__)


def load_config() -> Dict:
    """Load configuration from config.yaml."""
    with open("config/config.yaml", "r") as file:
        config = yaml.safe_load(file)
    logger.info("Configuration loaded")
    return config


def get_google_sheets_service(config: Dict):
    """Authenticate and return Google Sheets service."""
    creds = service_account.Credentials.from_service_account_file(
        config["google_sheets"]["credentials_file"],
        scopes=["https://www.googleapis.com/auth/spreadsheets"]
    )
    return build("sheets", "v4", credentials=creds)


def get_pending_briefs(service, config: Dict) -> List[Dict]:
    """Fetch pending client briefs from Google Sheets."""
    sheet = service.spreadsheets()
    result = sheet.values().get(
        spreadsheetId=config["google_sheets"]["spreadsheet_id"],
        range=f"{config['google_sheets']['sheet_name']}!A:I"
    ).execute()
    
    rows = result.get("values", [])
    if not rows or len(rows) < 2:
        return []
    
    headers = rows[0]
    briefs = []
    
    for i, row in enumerate(rows[1:], start=2):
        while len(row) < len(headers):
            row.append("")
        
        if row[8].lower() == "pending":
            brief = {
                "client_name": row[0],
                "offer_type": row[1],
                "offer_title": row[2],
                "target_audience": row[3],
                "tone": row[4],
                "key_benefit": row[5],
                "pain_point": row[6],
                "cta": row[7],
                "status": row[8],
                "row_index": i
            }
            briefs.append(brief)
    
    logger.info(f"Found {len(briefs)} pending briefs")
    return briefs


def send_to_slack(message: str, brief: Dict, config: Dict, thread_ts: str = None):
    """Send a message to Slack channel."""
    client = WebClient(token=config["slack"]["token"])
    
    if len(message) > 3000:
        message = message[:2997] + "..."
    
    response = client.chat_postMessage(
        channel=config["slack"]["channel"],
        text=message,
        thread_ts=thread_ts
    )
    logger.info(f"Message sent: {response['ts']}")
    return response['ts']


def save_to_google_docs(content: str, brief: Dict, config: Dict) -> str:
    """Save generated copy to Google Docs."""
    creds = service_account.Credentials.from_service_account_file(
        config["google_docs"]["credentials_file"],
        scopes=[
            "https://www.googleapis.com/auth/documents",
            "https://www.googleapis.com/auth/drive"
        ]
    )
    
    docs_service = build("docs", "v1", credentials=creds)
    drive_service = build("drive", "v3", credentials=creds)
    
    doc_title = f"DM Funnel - {brief['client_name']} - {brief['offer_title']}"
    
    doc = docs_service.documents().create(body={"title": doc_title}).execute()
    doc_id = doc.get("documentId")
    
    requests = [{
        "insertText": {
            "location": {"index": 1},
            "text": content
        }
    }]
    
    docs_service.documents().batchUpdate(
        documentId=doc_id,
        body={"requests": requests}
    ).execute()
    
    file = drive_service.files().get(fileId=doc_id, fields="parents").execute()
    previous_parents = ",".join(file.get("parents", []))
    
    drive_service.files().update(
        fileId=doc_id,
        addParents=config["google_docs"]["folder_id"],
        removeParents=previous_parents,
        fields="id, parents"
    ).execute()
    
    logger.info(f"Saved to Docs: {doc_id}")
    return doc_id


def update_google_sheet_status(service, config: Dict, row_index: int, status: str = "processed"):
    """Update brief status in Google Sheets."""
    sheet = service.spreadsheets()
    sheet.values().update(
        spreadsheetId=config["google_sheets"]["spreadsheet_id"],
        range=f"{config['google_sheets']['sheet_name']}!I{row_index}",
        valueInputOption="RAW",
        body={"values": [[status]]}
    ).execute()
    logger.info(f"Row {row_index} → {status}")
