CfhighlanderTemplate do
  Name 'jcasc-pipeline'
  Description "jcasc-pipeline - #{component_version}"

  DependsOn 'lib-iam@0.1.0'

  Parameters do
    ComponentParam 'EnvironmentName', 'dev', isGlobal: true
    ComponentParam 'EnvironmentType', 'development', allowedValues: ['development','production'], isGlobal: true
    ComponentParam 'VPC', type: 'AWS::EC2::VPC::Id'
    ComponentParam 'VPCEndpointId'
    ComponentParam 'SubnetIds', type: 'CommaDelimitedList'
    ComponentParam 'JenkinsInternalUrl'
    ComponentParam 'JenkinsExternalUrl'
    ComponentParam 'JenkinsUser'
  end

  LambdaFunctions 'repository_seeder_custom_resources'
  
end
