import boto3
import logging
from crhelper import CfnResource

logger = logging.getLogger(__name__)
helper = CfnResource(json_logging=False, log_level='INFO', boto_level='CRITICAL')

FILES = [
    'README.md',
    'jenkins.yaml'
]

@helper.create
def create(event, context):
    logger.info(f"Creating resource {event}")    
    create_event(event)
    return event['ResourceProperties']['Name']


@helper.update
def update(event, context):
    logger.info(f"Updating resource {event}")
    return event['ResourceProperties']['Name']


@helper.delete
def delete(event, context):
    logger.info(f"Deleting resource {event}")


def commit_default_jcacs(event):
    client = boto3.client('codecommit')
    try:
        client.create_commit(
            repositoryName=event['ResourceProperties']['RepositoryName'],
            branchName='master',
            authorName='ciinabox',
            email='ciinabox@base2services.com',
            commitMessage='initial jcasc commit',
            putFiles=load_files()
        )
    except client.exceptions.ParentCommitIdRequiredException as e:
        logger.error('repo already contains a commit')

def load_files():
    put_files = []
    for file in FILES:
        with open(file,'rb') as f:
            put_files.append({
                'filePath': file,
                'fileMode': 'NORMAL',
                'fileContent': f.read(),
            })
    return put_files

def handler(event, context):
    helper(event, context)