require 'yaml'

CloudFormation do
  
  jcasc_tags = []
  jcasc_tags.push({ Key: 'Name', Value: FnSub("${EnvironmentName}-#{component_name}") })
  jcasc_tags.push({ Key: 'EnvironmentName', Value: Ref(:EnvironmentName) })
  jcasc_tags.push({ Key: 'EnvironmentType', Value: Ref(:EnvironmentType) })
  jcasc_tags.push(*tags.map {|k,v| {Key: k, Value: FnSub(v)}}).uniq { |h| h[:Key] } if defined? tags
  
  S3_Bucket(:Bucket) {
    DeletionPolicy 'Retain'
    BucketName FnSub(bucket_name)
  }
  
  bucket_policy = {
    Statement: [{
      Sid: "jcasc-vpce",
      Effect: "Allow",
      Principal: "*",
      Action: [
        "s3:GetObject",
        "s3:PutObject"
      ],
      Resource: "arn:aws:s3:::${Bucket}/*",
      Condition: {
        StringLike: {
          "aws:sourceVpce" => "${VPCEndpointId}"
        }
      }
    }]
  }
  
  S3_BucketPolicy(:Policy) {
    Bucket Ref(:Bucket)
    PolicyDocument FnSub(bucket_policy.to_json)
  }
  
  IAM_Role(:CodeBuildRole) {
    Path '/'
    AssumeRolePolicyDocument service_assume_role_policy('codebuild')
    Policies iam_role_policies(codebuild_iam_policies)
  }
  
  Logs_LogGroup(:Logs) {
    LogGroupName FnSub("/${EnvironmentName}/codebuild/jcasc")
    RetentionInDays 7
  }
  
  EC2_SecurityGroup(:SecurityGroup) {
    GroupDescription FnSub("${EnvironmentName} JCasC pipeline for codebuild")
    VpcId Ref(:VPC)
    Tags jcasc_tags
  }
  
  CodeCommit_Repository(:Repository) {
    RepositoryDescription 'Jenkins configuration as code plugin source'
    RepositoryName FnSub("${EnvironmentName}-jcasc")
    Tags jcasc_tags
  }
  
  CodeBuild_Project(:Build) {
    Name FnSub("${EnvironmentName}-jcasc")
    Description FnSub("Validation and update of Jenkins CasC yaml")
    ServiceRole Ref(:CodeBuildRole)
    LogsConfig({
      CloudWatchLogs: {
        GroupName: Ref(:Logs),
        Status: 'ENABLED'
      }
    })
    VpcConfig({
      SecurityGroupIds: [ Ref(:SecurityGroup)],
      Subnets: Ref(:SubnetIds),
      VpcId: Ref(:VPC)
    })
    Source({
      Type: 'CODECOMMIT',
      Location: FnGetAtt(:Repository, :CloneUrlHttp),
      BuildSpec: buildspec.to_yaml
    })
    Environment({
      ComputeType: 'BUILD_GENERAL1_SMALL',
      Image: 'aws/codebuild/amazonlinux2-x86_64-standard:2.0',
      Type: 'LINUX_CONTAINER',
      ImagePullCredentialsType: 'CODEBUILD',
      EnvironmentVariables: [
        {
          Name: 'BUCKET',
          Value: Ref(:Bucket)
        },
        {
          Name: 'ENVIRONMENT_NAME',
          Value: Ref(:EnvironmentName)
        },
        {
          Name: 'JENKINS_URL',
          Value: Ref(:JenkinsUrl)
        },
        {
          Name: 'JENKINS_API_USER',
          Value: Ref(:JenkinsUser)
        },
        {
          Name: 'JENKINS_API_PASSWORD',
          Value: FnSub("/${EnvironmentName}/jenkins/admin/password"),
          Type: 'SECRETS_MANAGER'
        }
      ]
    })
    Artifacts({
      Type: 'NO_ARTIFACTS'
    })
  }
  
  IAM_Role(:TriggerRole) {
    Path '/'
    AssumeRolePolicyDocument service_assume_role_policy('events')
    Policies iam_role_policies(trigger_iam_policies)
  }
  
  Events_Rule(:Trigger) {
    EventPattern({
      source: [
        'aws.codecommit'
      ],
      'detail-type': [
        'CodeCommit Repository State Change'
      ],
      resources: [ 
        FnSub("arn:aws:codecommit:${AWS::Region}:${AWS::AccountId}:${EnvironmentName}-jcasc") 
      ],
      detail: {
        event: [
          'referenceCreated',
          'referenceUpdated'
        ],
        referenceType: [
          'branch'
        ],
        referenceName: [
          'master'
        ]
      }
    })
    Targets([
        {
          Arn: FnSub("arn:aws:codebuild:${AWS::Region}:${AWS::AccountId}:project/${Build}"),
          RoleArn: FnGetAtt(:TriggerRole, :Arn),
          Id: 'jcasc-codebuild-trigger'
        }
    ])
  }
  
  SecretsManager_Secret(:JenkinsSecret) {
    Description FnSub("${EnvironmentName} Jenkins auto generated admin password")
    GenerateSecretString ({
      ExcludePunctuation: true,
      PasswordLength: 32
    })
    Name FnSub("/${EnvironmentName}/jenkins/admin/password")
    Tags jcasc_tags
  }
  
  Output(:JenkinsSecret) {
    Value Ref(:JenkinsSecret)
  }
  
  Resource(:SeedRepository) {
    DependsOn [:Build,:Trigger]
    Type "Custom::SeedRepository"
    Property('ServiceToken', FnGetAtt(:RepositorySeederCR, :Arn))
    Property('RepositoryName', FnGetAtt(:Repository, :Name))
    Property('JenkinsUrl', Ref(:JenkinsUrl))
  }
  
  Output(:FileLocation) {
    Value FnSub("https://s3-${AWS::Region}.amazonaws.com/${Bucket}/${EnvironmentName}/jenkins.yaml")
  }
  
end
