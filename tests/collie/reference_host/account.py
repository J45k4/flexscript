"""Bounded account metadata for display; never an authentication decision."""
import base64
import json

AUTH_CLAIM = 'https://api.openai.com/auth'
PROFILE_CLAIM = 'https://api.openai.com/profile'


def text(value, limit=256):
    if not isinstance(value, str) or len(value)>limit:
        return ''
    return ''.join(c for c in value if c.isprintable()).strip()


def claims(token):
    if not isinstance(token, str) or len(token)>65536:
        return {}
    parts=token.split('.')
    if len(parts)!=3:
        return {}
    try:
        payload=base64.b64decode(parts[1]+'='*(-len(parts[1])%4), altchars=b'-_', validate=True)
        result=json.loads(payload)
        return result if isinstance(result,dict) else {}
    except (ValueError, UnicodeError, RecursionError):
        return {}


def account_details(auth):
    if not isinstance(auth,dict) or auth.get('auth_mode')!='chatgpt':
        return {}
    tokens=auth.get('tokens')
    if not isinstance(tokens,dict) or not isinstance(tokens.get('access_token'),str) or not tokens['access_token']:
        return {}
    access=claims(tokens['access_token']);identity=claims(tokens.get('id_token'))
    profile=access.get(PROFILE_CLAIM,{})
    if not isinstance(profile,dict):profile={}
    # Export only display fields. Tokens, profile pictures and arbitrary claims
    # never enter UI state, conversation history or guest VM inputs.
    details={key:value for key,value in dict(
        name=text(profile.get('name'),160) or text(identity.get('name'),160),
        email=text(profile.get('email'),254) or text(identity.get('email'),254),
        account_id=text(tokens.get('account_id'))).items() if value}
    for payload in (access,identity):
        account=payload.get(AUTH_CLAIM,{})
        if not isinstance(account,dict):continue
        # A selected workspace can differ from an ID token's default account.
        # Show a plan only when it belongs to the transport's selected account.
        if details.get('account_id') and account.get('chatgpt_account_id')==details['account_id']:
            plan=text(account.get('chatgpt_plan_type'),64)
            if plan:
                details['plan']=plan.replace('_',' ').title()
                break
    return details
