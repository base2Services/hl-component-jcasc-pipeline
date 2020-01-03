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
    commit_default_jcacs(event)
    return event['ResourceProperties']['RepositoryName']


@helper.update
def update(event, context):
    logger.info(f"Updating resource {event}")
    return event['ResourceProperties']['RepositoryName']


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
            putFiles=load_files(
                client.meta.region_name,
                event['ResourceProperties']['JenkinsUrl'])
                event['ResourceProperties']['CiinaboxName'])
        )
    except client.exceptions.ParentCommitIdRequiredException as e:
        logger.error('repo already contains a commit')

def load_files(region,url,ciinabox_name):
    put_files = []
    for filename in FILES:
        with open(filename,'r') as file:
            fileContent = file.read()
            fileContent = fileContent.replace('{{ciinabox::region}}', region)
            fileContent = fileContent.replace('{{ciinabox::url}}', url)
            fileContent = fileContent.replace('{{ciinabox::name}}', ciinabox_name)
            put_files.append({
                'filePath': filename,
                'fileMode': 'NORMAL',
                'fileContent': str.encode(fileContent)
            })
    return put_files


def lambda_handler(event, context):
    helper(event, context)