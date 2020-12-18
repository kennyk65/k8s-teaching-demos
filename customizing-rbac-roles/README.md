# Demo Instructions

1.  Make a play namespace:
kubectl create namespace web

2.  Create a role by running web-admins-role.yaml:
kubectl apply -f https://raw.githubusercontent.com/kennyk65/k8s-teaching-demos/master/customizing-rbac-roles/web-admins-role.yaml

3.  Bind it to a group:
kubectl apply -f https://raw.githubusercontent.com/kennyk65/k8s-teaching-demos/master/customizing-rbac-roles/web-admins-rolebinding.yaml

4.  Edit the aws-auth ConfigMap:
kubectl edit configmap -n kube-system aws-auth

insert this:
	- groups:
      - web-admins
      rolearn: arn:aws:iam::123456789012:role/WebAdminRole
      username: web-admin

In editor, "i" puts you in insert mode, 'esc' takes you out, ':wq" saves changes.

5  Describe
kubectl describe configmap aws-auth -n kube-system

Note that this is not a real role.  But we could make one.  And that role would be able to use kubectl to do anything in the web namespace, but nowhere else.


