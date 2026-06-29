"""LangChain chain definitions for DM funnel generation."""
from langchain_anthropic import ChatAnthropic
from langchain_core.prompts import ChatPromptTemplate
from langchain_core.output_parsers import StrOutputParser
import logging

logger = logging.getLogger(__name__)


def load_prompt(offer_type: str) -> ChatPromptTemplate:
    """Load a markdown prompt template and convert to LangChain format."""
    try:
        with open(f"prompts/{offer_type}.md", "r") as file:
            prompt_template = file.read()
        
        prompt = ChatPromptTemplate.from_template(prompt_template)
        logger.info(f"Loaded prompt template for: {offer_type}")
        return prompt
    except FileNotFoundError:
        logger.error(f"Prompt file not found: prompts/{offer_type}.md")
        raise


def get_funnel_generation_chain(config: dict):
    """Create the base LangChain chain for funnel generation."""
    llm = ChatAnthropic(
        model="claude-3-opus-20240229",
        temperature=0.7,
        max_tokens=1000,
        anthropic_api_key=config["claude_api_key"]
    )
    
    chain = llm | StrOutputParser()
    logger.info("Created funnel generation chain with Claude 3 Opus")
    return chain


def generate_dm_funnel(brief: dict, config: dict) -> str:
    """Generate a single DM funnel variant."""
    prompt = load_prompt(brief['offer_type'])
    chain = get_funnel_generation_chain(config)
    
    variables = {
        "TITLE": brief['offer_title'],
        "TONE": brief['tone'],
        "RESULT": brief['key_benefit'],
        "PAIN_POINT": brief['pain_point'],
        "CTA": brief['cta']
    }
    
    final_chain = prompt | chain
    return final_chain.invoke(variables)


def generate_dm_funnel_variants(brief: dict, config: dict) -> dict:
    """Generate 3 tonal variants of a DM funnel."""
    variants_config = {
        "variant_direct": {
            **brief,
            "tone": "Direct, data-driven, and no-fluff. Use strong, confident language."
        },
        "variant_inspirational": {
            **brief,
            "tone": "Inspirational and visionary. Focus on transformation and possibility."
        },
        "variant_curious": {
            **brief,
            "tone": "Mysterious and curiosity-sparking. Use pattern interrupts and intrigue."
        }
    }
    
    results = {}
    for variant_name, variant_brief in variants_config.items():
        try:
            results[variant_name] = generate_dm_funnel(variant_brief, config)
            logger.info(f"Generated {variant_name}")
        except Exception as e:
            logger.error(f"Failed: {variant_name}: {e}")
            results[variant_name] = f"Error: {str(e)}"
    
    return results
