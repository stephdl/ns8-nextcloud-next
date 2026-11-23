*** Settings ***
Library    SSHLibrary
Resource    api.resource

*** Variables ***
${nc_url}    https://127.0.0.1
${configure_exapps_on}    {"host": "nextcloud.dom.test", "lets_encrypt": false, "domain": "", "password": "Nethesis,1234", "internal_smarthost": false, "exapps": true}

*** Keywords ***
Module environment
    [Arguments]    ${name}
    ${out} =    Execute Command    runagent -m ${module_id} printenv ${name}
    RETURN    ${out.strip()}

Read the file of u1
    ${out} =    Execute Command    curl -sk -f -u u1:${u1_password} -H "Host: nextcloud.dom.test" ${nc_url}/remote.php/dav/files/u1/upgrade.txt
    RETURN    ${out}

The restore has run
    # Without it the checks below would pass against the old module.
    Should Be True    ${restored}    the restore did not complete

The reinstall has finished
    ${rc} =    Execute Command    runagent -m ${module_id} systemctl --user is-active nextcloud-exapps-reinstall
    ...    return_rc=True    return_stdout=False
    Should Not Be Equal As Integers    ${rc}    0

*** Test Cases ***
Install an External App before the backup
    Run task    module/${module_id}/configure-module    ${configure_exapps_on}    decode_json=${FALSE}
    ${rc} =    Execute Command
    ...    runagent -m ${module_id} occ app_api:app:register test-deploy harp_proxy --info-xml https://raw.githubusercontent.com/nextcloud/test-deploy/main/appinfo/info.xml --wait-finish
    ...    return_rc=True    return_stdout=False
    Should Be Equal As Integers    ${rc}    0
    ${out} =    Execute Command    runagent -m ${module_id} occ app_api:app:list
    Should Contain    ${out}    test-deploy

Record the instance before the backup
    ${file} =    Read the file of u1
    Should Not Be Empty    ${file}
    ${uuid} =    Module environment    MODULE_UUID
    ${node} =    Module environment    NODE_ID
    ${port} =    Module environment    TCP_PORT
    Set Suite Variable    ${u1_file}    ${file}
    Set Suite Variable    ${module_uuid}    ${uuid}
    Set Suite Variable    ${module_node}    ${node}
    Set Suite Variable    ${old_port}    ${port}
    Set Suite Variable    ${old_module_id}    ${module_id}
    Set Suite Variable    ${restored}    ${FALSE}

Use the node local backup repository
    # A repository URL must be unique: reuse the node's one if it exists.
    ${ip} =    Execute Command    redis-cli hget node/${module_node}/vpn ip_address
    ${url} =    Set Variable    webdav:http://${ip.strip()}:4694
    ${repos} =    Run task    cluster/list-backup-repositories    {}
    ${found} =    Evaluate    [r['id'] for r in $repos['repositories'] if r['url'] == $url]
    IF    ${found}
        Set Suite Variable    ${repository}    ${found}[0]
        Set Suite Variable    ${repository_created}    ${FALSE}
    ELSE
        ${out} =    Run task    cluster/add-backup-repository
        ...    {"provider":"cluster","name":"nextcloud-test","url":"${url}","password":"","parameters":{}}
        Set Suite Variable    ${repository}    ${out}[id]
        Set Suite Variable    ${repository_created}    ${TRUE}
    END

Back up nextcloud
    # run-backup skips a disabled backup, so enable it on a far schedule.
    ${bid} =    Run task    cluster/add-backup
    ...    {"name":"nextcloud-test","instances":["${module_id}"],"repository":"${repository}","schedule":"*-12-31 03:17:00","retention":1,"enabled":true}
    Set Suite Variable    ${backup_id}    ${bid}
    # Synchronous: it returns once every node has finished its part.
    Run task    cluster/run-backup    {"id":${backup_id}}
    ${snapshots} =    Run task    cluster/read-backup-snapshots
    ...    {"repository":"${repository}","path":"nextcloud-next/${module_uuid}"}
    Should Not Be Empty    ${snapshots}
    Set Suite Variable    ${snapshot}    ${snapshots}[-1][id]

Restore nextcloud in place
    # The restored instance gets new ports: the case that broke the HaRP daemon.
    ${out} =    Run task    cluster/restore-module
    ...    {"repository":"${repository}","path":"nextcloud-next/${module_uuid}","snapshot":"${snapshot}","node":${module_node},"replace":true}
    Should Be Equal    ${out}[module_uuid]    ${module_uuid}
    Should Not Be Equal    ${out}[module_id]    ${old_module_id}
    Set Global Variable    ${module_id}    ${out}[module_id]
    Set Suite Variable    ${restored}    ${TRUE}
    ${rc} =    Execute Command    runagent -m ${old_module_id} true
    ...    return_rc=True    return_stdout=False
    Should Not Be Equal As Integers    ${rc}    0    ${old_module_id} must be gone after a replace

Nextcloud runs again after the restore
    [Setup]    The restore has run
    ${out} =    Execute Command    runagent -m ${module_id} occ status --output=json
    &{status} =    Evaluate    json.loads($out)    modules=json
    Should Be True    ${status.installed}
    Should Not Be True    ${status.maintenance}

The files are restored as they were
    [Setup]    The restore has run
    ${file} =    Read the file of u1
    Should Be Equal    ${file}    ${u1_file}

The HaRP daemon uses the ports of the restored instance
    [Setup]    The restore has run
    ${port} =    Module environment    TCP_PORT
    ${frp} =    Module environment    HARP_FRP_PORT
    Should Not Be Equal    ${port}    ${old_port}
    ${out} =    Execute Command    runagent -m ${module_id} systemctl --user is-active nextcloud-harp
    Should Be Equal    ${out}    active
    ${out} =    Execute Command    runagent -m ${module_id} occ app_api:daemon:list --output=json
    Should Contain    ${out}    "nextcloud_url":"http:\\/\\/127.0.0.1:${port}"
    Should Contain    ${out}    "frp_address":"127.0.0.1:${frp}"

The External Apps are installed again in the background
    [Setup]    The restore has run
    # test-deploy is not in the app store, so its reinstall fails and stays listed
    Wait Until Keyword Succeeds    10 minutes    10 seconds    The reinstall has finished
    ${out} =    Execute Command    runagent -m ${module_id} cat exapps-reinstall
    Should Contain    ${out}    test-deploy enabled
    ${out} =    Execute Command    runagent -m ${module_id} occ app_api:app:list
    Should Not Contain    ${out}    test-deploy

Remove the test backup
    Run task    cluster/remove-backup    {"id":${backup_id}}
    IF    ${repository_created}
        Run task    cluster/remove-backup-repository    {"id":"${repository}"}
    END
