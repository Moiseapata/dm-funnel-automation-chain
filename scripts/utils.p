"""Utility functions for Google Sheets, Slack, and Google Docs."""
import yaml
import os
import logging
from typing import Dict, List
from dotenv import load_dotenv  # ← AJOUTEZ
from google.oauth2 import service_account
from googleapiclient.discovery import build
from slack_sdk import WebClient
from slack_sdk.errors import SlackApiError

# Load .env file
load_dotenv()  # ← AJOUTEZ

logger = logging.getLogger(__name__)


def load_config() -> Dict:
    """Load configuration from config.yaml with env var overrides."""
    with open("config/config.yaml", "r") as file:
        config = yaml.safe_load(file)
    
    # Override with environment variables if they exist
    if os.getenv("CLAUDE_API_KEY"):
        config["claude_api_key"] = os.getenv("CLAUDE_API_KEY")
    if os.getenv("SLACK_BOT_TOKEN"):
        config["slack"]["token"] = os.getenv("SLACK_BOT_TOKEN")
    if os.getenv("SPREADSHEET_ID"):
        config["google_sheets"]["spreadsheet_id"] = os.getenv("SPREADSHEET_ID")
    if os.getenv("GOOGLE_DRIVE_FOLDER_ID"):
        config["google_docs"]["folder_id"] = os.getenv("GOOGLE_DRIVE_FOLDER_ID")
    
    logger.info("Configuration loaded")
    return config


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
    
    # CORRECTION DU BUG: Vérifier si le fichier a des parents
    file = drive_service.files().get(fileId=doc_id, fields="parents").execute()
    previous_parents = ",".join(file.get("parents", []))
    
    # Ne déplacer que si nécessaire
    if previous_parents:
        drive_service.files().update(
            fileId=doc_id,
            addParents=config["google_docs"]["folder_id"],
            removeParents=previous_parents,
            fields="id, parents"
        ).execute()
    else:
        # Si pas de parents, juste ajouter au dossier cible
        drive_service.files().update(
            fileId=doc_id,
            addParents=config["google_docs"]["folder_id"],
            fields="id, parents"
        ).execute()
    
    logger.info(f"Saved to Docs: {doc_id}")
    return doc_id

# ... le reste du fichier reste identique
