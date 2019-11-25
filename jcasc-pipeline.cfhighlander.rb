CfhighlanderTemplate do
  Name 'jcasc-pipeline'
  Description "jcasc-pipeline - #{component_version}"

  Parameters do
    ComponentParam 'EnvironmentName', 'dev', isGlobal: true
    ComponentParam 'EnvironmentType', 'development', allowedValues: ['development','production'], isGlobal: true
    ComponentParam 'VPC', type: 'AWS::EC2::VPC::Id'
    ComponentParam 'VPCEndpointId'
    ComponentParam 'SubnetIds', type: 'CommaDelimitedList'
    ComponentParam 'JenkinsUrl'
  end


end
