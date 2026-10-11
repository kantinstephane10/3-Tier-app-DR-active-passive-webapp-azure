import json,subprocess,sys

def az(*args):
    return json.loads(subprocess.check_output(['az',*args,'--output','json'],text=True))
for region,target in json.load(open(sys.argv[1])).items():
    rg,vault,policy=target['resource_group'],target['vault'],target['policy']
    vms=az('vm','list','--resource-group',rg)
    items=az('backup','item','list','--resource-group',rg,'--vault-name',vault)
    protected={i.get('properties',{}).get('sourceResourceId','').lower() for i in items if i.get('properties',{}).get('protectionState')=='Protected'}
    for v in vms:
        if not v.get('virtualMachineScaleSet'):continue
        if v['id'].lower() in protected:
            print(region,v['name'],'already protected');continue
        subprocess.run(['az','backup','protection','enable-for-vm','--resource-group',rg,'--vault-name',vault,'--policy-name',policy,'--vm',v['id'],'--output','none'],check=True)
        print(region,v['name'],'backup enabled')
print('Reconciliation complete. Confirm recovery points after the first scheduled backup.')
