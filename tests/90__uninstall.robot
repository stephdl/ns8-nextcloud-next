*** Settings ***
Library    SSHLibrary

*** Variables ***
${SCENARIO}    install

*** Test Cases ***
Check if nextcloud is removed correctly
    ${rc} =    Execute Command    remove-module --no-preserve ${module_id}
    ...    return_rc=True  return_stdout=False
    Should Be Equal As Integers    ${rc}  0
    IF    '${SCENARIO}' == 'update'
        Execute Command    api-cli run remove-repository --data '{"name":"stephdl"}'
    END
