EnsembleWorkflow
==============
Restful web API for InterSystems Data Platforms Workflow. This is the latest version, previous projects are deprecated and should not be used in new projects.

## Installation
1. Import and compile this [isc.wf.REST](https://raw.githubusercontent.com/intersystems-ru/WorkflowAPI/master/isc/wf/REST.cls).
2. Create a web-application for REST in the Portal Management System (for ex. `/csp/workflow/rest`). Set dispatch class to `isc.wf.REST`, Authentication methods to 'Unauthorized' and 'Password'.
3. (Optional) Add `isc.wf` package mapping if you need to query another namespace.


##Requests

These are the possible requests to web application. [Postman collection is available](https://raw.githubusercontent.com/intersystems-ru/WorkflowAPI/master/WorkflowAPI.postman_collection.json).

| URL                         | Type | Response  | Description                    |
|-----------------------------|------|-----------|--------------------------------|
| tasks/:count/:maxId         | GET  | JSON      | Get unassigned tasks or tasks assigned to the current user. Params optional |
| task/:id                    | GET  | JSON      | Get detailed information about a task |
| task/:id                    | POST | JSON      | Process task modified by a user|
| test                        | GET  | JSON      | Test info                      |


## Prerequisites

If you work with Ensemble Workflow it is recommended to familiarize yourself with [EnsLib.Workflow](http://docs.intersystems.com/latest/csp/documatic/%25CSP.Documatic.cls?PAGE=CLASS&LIBRARY=ENSLIB&PACKAGE=1&CLASSNAME=EnsLib.Workflow) package. Here's a quick primer on the main classes:

| Class                            | Description                                                                                                                                                                                                                                                                                                    | 
|----------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------| 
| EnsLib.Workflow.ActionDefinition | Defines the set of available actions that a user can make within a Workflow application. Users can extend this list.                                                                                                                                                                                           | 
| EnsLib.Workflow.Engine           | Provides the core APIs for the Ensemble Workflow system.                                                                                                                                                                                                                                                       | 
| EnsLib.Workflow.FormEngine       | Provides the API for managing form associated with Workflow tasks.                                                                                                                                                                                                                                             | 
| EnsLib.Workflow.Operation        | This Business Operation manages the delegation of workflow tasks to the Ensemble Workflow Engine.                                                                                                                                                                                                              | 
| EnsLib.Workflow.RoleDefinition   | Defines a workflow role and its members.                                                                                                                                                                                                                                                                       | 
| EnsLib.Workflow.RoleMembership   | Manages the many-to-many relationship of workflow Users and Roles. Each instance represents the association of a specific User with a specific Role.                                                                                                                                                           | 
| EnsLib.Workflow.TaskRequest      | A task is a specialized request for a user action (it is used as part of a Workflow application).                                                                                                                                                                                                              | 
| EnsLib.Workflow.TaskResponse     | Response from a Workflow Task request. The Workflow Engine creates an instance of TaskResponse object as soon it receives a TaskRequest. This object is used to maintain the status of the task while it is under the control of the Workflow Engine. It also serves as the final response returned by the Workflow Engine when the task is complete.| 
| EnsLib.Workflow.TaskStatus       | Holds Task Status details used by Workflow Engine to manage tasks.                                                                                                                                                                                                                                             | 
| EnsLib.Workflow.UserDefinition   | Defines a workflow user. Typically the user name matches a system user name but this is not required. Workflow users that are not registered system users will not be able to log into the Workflow portal and check the status of their worklist.                                                             |  
| EnsLib.Workflow.Worklist         | Represents a worklist item associated with a User within a Workflow application.                                                                                                                                                                                                                               | 


## GET tasks 

It's the basic and first request you need to execute after logging in (by authentication method you configured for REST web application). It returns basic information unassigned tasks or tasks assigned to a current user. 
You can provide two parameters: 

- `count` - number of records to return (defaults to 100)
- `maxId` - last id from previous page (if left empty all tasks would be returned)

Tasks are returned in reverse chronological order, newest to oldest. Here's how it looks like:

```
[
    {
        "id": "318||dev",
        "isNew": 1,
        "priority": 3,
        "subject": "Problem reported by 1",
        "message": "2",
        "timeCreated": "2018-08-24 07:07:22.717",
        "role": "Demo-Development"
    },
    {
        "id": "313||dev",
        "isNew": 0,
        "priority": 3,
        "subject": "Problem reported by 4",
        "message": "4",
        "timeCreated": "2018-06-18 09:18:35.881",
        "role": "Demo-Development"
    }
]
```
Here we can see two tasks, fist unassigned and second assigned to a current user (dev). Object properties are 

| Property    | Description                                                                        | Value                                                  | 
|-------------|------------------------------------------------------------------------------------|--------------------------------------------------------| 
| id          | Id of this EnsLib.Workflow.Worklist                                                |                                                        | 
| isNew       | Has the user accepted this item yet?                                               | 1 for no (new), 0 for yes (accepted)                   | 
| priority    | Priority of the requested Task                                                     | 1 is highest                                           | 
| subject     | Short summary of this task                                                         |                                                        | 
| message     | Detailed message body for this task                                                | First 25 symbols only                                  | 
| timeCreated | Creation time                                                                      | UTC timestamp                                          | 
| role        | The workflow role (EnsLib.Workflow.RoleDefinition)                                 |                                                        | 

## GET task/:id

After you received main information about available tasks, you can see it in more detail, by requesting it by id (`308||dev` in the example). Here's how response object looks like:

```
{
    "id": "308||dev",
    "isNew": 1,
    "priority": 3,
    "subject": "Problem reported by 3",
    "message": "3",
    "timeCreated": "2018-11-28 19:03:41.95",
    "role": "Demo-Development",
    "actions": "Corrected,Ignored",
    "formFields": {
        "Comments": "Comment value, if any"
    }
}
```

Properties are the same, except two new properties are added

| Property    | Description                                                                        | Value                                                                            | 
|-------------|------------------------------------------------------------------------------------|----------------------------------------------------------------------------------| 
| actions     | List of possible actions                                                           | Comma separated. Does not include systems actions $Accept, $Relinquish and $Save | 
| formFields  | Object with fields and their values                                                | JSON Object                                                                      | 


It's just a JSON representation of [EnsLib.Workflow.Worklist](http://docs.intersystems.com/latest/csp/documatic/%25CSP.Documatic.cls?PAGE=CLASS&LIBRARY=ENSLIB&CLASSNAME=EnsLib.Workflow.Worklist) object.
This request provides enough information to display task to the user.

##  POST task/:id

After a user is done working on a task, you need to notify Workflow engine about a new state of a task. To do that, execute this request, with the JSON representation of EnsLib.Workflow.Worklist object (received from the previous request) as a body.
To express changes made by a user, send this object:

- Set `action` property to one of the %Actions values or `$Accept` to accept a task, `$Relinquish` to relinquish task and `$Save` to save changes made to a task
- Provide `formValues` object with ALL values, even unmodified ones. 

Here's an example of a user modifying `308||dev` task (by choosing Save action):

```
{
	"action": "$Save", 
	"formFields": {
		"Comments": "New comment value"
	}
}
```
