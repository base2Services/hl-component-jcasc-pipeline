require 'yaml'

CloudFormation do
  
  jcasc_tags = []
  jcasc_tags.push({ Key: 'Name', Value: FnSub("${EnvironmentName}-#{component_name}") })
  jcasc_tags.push({ Key: 'EnvironmentName', Value: Ref(:EnvironmentName) })
  jcasc_tags.push({ Key: 'EnvironmentType', Value: Ref(:EnvironmentType) })
  jcasc_tags.push(*tags.map {|k,v| {Key: k, Value: FnSub(v)}}).uniq { |h| h[:Key] } if defined? tags
  
  policies = []
  iam_policies.each do |name,policy|
    policies << iam_policy_allow(name,policy['action'],policy['resource'] || '*')
  end if defined? iam_policies
  
  S3_Bucket(:Bucket) {
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
    AssumeRolePolicyDocument service_role_assume_policy('codebuild')
    Policies policies
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
    RepositoryName FnSub("${EnvironmentName}-ciinabox-jcasc")
    Tags jcasc_tags
  }
  
  CodeBuild_Project(:Build) {
    Name FnSub("${EnvironmentName}-ciinabox-jcasc-validation")
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
      Image: 'python:3.7-alpine',
      Type: 'LINUX_CONTAINER',
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
          Value: FnSub("/${EnvironmentName}/jenkins/username"),
          Type: 'PARAMETER_STORE'
        },
        {
          Name: 'JENKINS_API_PASSWORD',
          Value: FnSub("/${EnvironmentName}/jenkins/password"),
          Type: 'PARAMETER_STORE'
        }
      ]
    })
    Artifacts({
      Type: 'NO_ARTIFACTS'
    })
  }
  
  IAM_Role(:TriggerRole) {
    Path '/'
    AssumeRolePolicyDocument service_role_assume_policy('events')
    Policies([
      iam_policy_allow(
        'CloudWatchEventPolicy',
        %w(codebuild:StartBuild),
        FnGetAtt(:Build, :Arn))
    ])
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
        FnSub("arn:aws:codecommit:${AWS::Region}:${AWS::AccountId}:${Repository}") 
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
  
  Output(:FileLocation) {
    Value FnSub("https://s3-${AWS::Region}.amazonaws.com/${Bucket}/${EnvironmentName}/jenkins.yaml")
  }
  
end
