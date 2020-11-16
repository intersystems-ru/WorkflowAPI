Class isc.wf.REST Extends %CSP.REST
{

Parameter CONTENTTYPE = "application/json";

Parameter CHARSET = "UTF-8";

Parameter UseSession As Integer = 1;

Parameter CONVERTINPUTSTREAM = 1;

XData UrlMap [ XMLNamespace = "http://www.intersystems.com/urlmap" ]
{
<Routes>
<Route Url="/tasks" Method="GET" Call="getTasks"/>
<Route Url="/tasks/:count" Method="GET" Call="getTasks"/>
<Route Url="/tasks/:count/:maxId" Method="GET" Call="getTasks"/>

<Route Url="/task/:id" Method="GET" Call="getTask"/>
<Route Url="/task/:id" Method="POST" Call="postTask"/>

<Route Url="/test" Method="GET" Call="test"/>
<Route Url="/logout" Method="GET" Call="logout"/>
<Route Url="/user-info" Method="GET" Call="getUserInfo"/>
</Routes>
}

/// End session
ClassMethod logout() As %Status
{
	#dim %session As %CSP.Session
	set sc = %session.Logout(1)
	set %session.EndSession = 1
	quit sc
}

/// Test method
ClassMethod test() As %Status
{
    write "{""Status"": ""OK""}"
    quit $$$OK
}

/// Get tasks. Supports pagination.
/// count - number of records to get
/// maxId - latest id, leave empty to start from the begining
/// set sc = ##class(isc.wf.REST).getTasks()
ClassMethod getTasks(count = 100, maxId = "") As %Status
{
	#dim sc As %Status = $$$OK
	#dim isFirst As %Boolean = $$$YES
	&sql(	DECLARE C1 CURSOR FOR
			SELECT TOP :count 
				 %ID,  IsNew,  Task->%Priority, Task->%Subject, Left(Task->%Message, 100), TimeCreated,  RoleName
			INTO :id, :isNew, :priority,        :subject,       :message,                  :timeCreated, :role
			FROM EnsLib_Workflow.Worklist
			WHERE (UserName = USER) 
				AND ((Task->TaskStatus_AssignedTo IS NULL) OR (Task->TaskStatus_AssignedTo = UserName))
				AND ((%ID < :maxId) OR (:maxId IS NULL))
			ORDER BY %ID DESC)
	&sql(OPEN C1)
	&sql(FETCH C1)
	write:((SQLCODE=0) || (SQLCODE=100)) "["
	while (SQLCODE = 0) {
		if isFirst {
			set isFirst = $$$NO
		} else {
			write ",",!
		}
		write "{""id"":""", id,""",",
		 			"""isNew"":",$case(isNew, $$$YES: "true", :"false"),",",
		 			"""priority"":",priority,",",
		 			"""subject"":""", $zcvt(subject,"O", "JSON"),""",",
		 			"""message"":""", $zcvt(message,"O", "JSON"),""",",
		 			"""timeCreated"":""", $tr(timeCreated, " ", "T") _ "Z",""",",
		 			"""role"":""", role,"""}"
		&sql(FETCH C1)
	}
	if (SQLCODE'=100) {
		set sc = $$$ERROR($$$SQLError, SQLCODE, $g(%msg))
	} else {
		write "]"
	}
	&sql(CLOSE C1)
	
	quit sc
}

/// Get one task
/// set sc = ##class(isc.wf.REST).getTask("318||dev")
ClassMethod getTask(id) As %Status
{
	#dim sc As %Status = $$$OK
	&sql(	SELECT %ID,  IsNew,  Task->%Priority, Task->%Subject, Task->%Message, TimeCreated,  RoleName,  Task,  Task->%Actions, Task->%FormFields
			INTO   :id, :isNew, :priority,        :subject,       :message,       :timeCreated, :role,     :task, :actions,       :formFields
			FROM EnsLib_Workflow.Worklist
			WHERE (%ID = :id) AND (UserName = USER))
	if (SQLCODE = 0) {
		write "{""id"":""", id,""",",
		 			"""isNew"":",$case(isNew, $$$YES: "true", :"false"),",",
		 			"""priority"":",priority,",",
		 			"""subject"":""",$zcvt(subject,"O", "JSON"),""",",
		 			"""message"":""",$zcvt(message,"O", "JSON"),""",",
		 			"""timeCreated"":""", $tr(timeCreated, " ", "T") _ "Z",""",",
		 			"""role"":""",role,""",",
		 			"""actions"":""",actions,""",",
		 			"""formFields"":{"
		 
		merge fieldValues = ^Ens.MessageBodyD(task, "%FormValues")	
		set fieldCount = $case(formFields, "":0, :$l(formFields, ","))
		for field = 1:1:fieldCount {
			set fieldName = $p(formFields, ",", field)
			continue:fieldName=""
			set fieldValue = $g(fieldValues(fieldName))
			
			// Special handlers
			// "$$$Handler": {"myLink":"link","myImg":"img"}
			if fieldName = "$$$Handler" {
				write """",$zcvt(fieldName,"O", "JSON"),""":",fieldValue
			} else {
				write """",$zcvt(fieldName,"O", "JSON"),""":""",$zcvt(fieldValue,"O", "JSON"),""""
			}
			write:(field<fieldCount) ","
		 }
		 write "}}"
	} else {
		set sc = $$$ERROR($$$SQLError, SQLCODE, $g(%msg))
	}
	
	quit sc
}

/// Submit task. Works only in CSP context
/// formFields - pass all field values as json object properties
/// { "action": "action1", "formFields": {}}
ClassMethod postTask(id As %String) As %Status
{
	#dim %request As %CSP.Request
	// For EnsLib.Workflow.FormEngine compatibility
	set %request.Data("$ITEMID",1) = id
	
	set taskResponse = ##class(EnsLib.Workflow.TaskResponse).%OpenId($p(id, "||", 1), , .sc)
	quit:$$$ISERR(sc) sc
	
	set owner = taskResponse.%TaskStatus.AssignedTo
	quit:((owner'=$username) && (owner '="")) $$$ERROR($$$GeneralError, "User " _ $username _ " does not have rights to modify this task")
	
	set %request.Content = {}.%FromJSON(%request.Content)
	set taskResponse.%Action = %request.Content.action
	
	set iterator = %request.Content.formFields.%GetIterator()
	while iterator.%GetNext(.key, .value) {
		set %request.Data(key,1) = value
	}
	
	quit ##class(EnsLib.Workflow.FormEngine).%OnSubmit(taskResponse, .msq)
}

/// Only Workflow users can use this api
ClassMethod OnPreDispatch(pUrl As %String, pMethod As %String, ByRef pContinue As %Boolean) As %Status
{
	set pContinue = ##class(EnsLib.Workflow.UserDefinition).%ExistsId($username)
	set:'pContinue %response.Status=..#HTTP403FORBIDDEN
    quit $$$OK
}

/// Called for a REST page in the event of a login being required
ClassMethod Login(skipheader As %Boolean = 1) As %Status [ ProcedureBlock = 0 ]
{
    #dim tSC As %Status = $$$OK
    #dim e As %Exception.AbstractException
    
    #dim tMatchURL As %String
			$$$SysLog(3,"OAuth2","[%CSP.REST]","Login: %request.Method="_%request.Method)
           
    Try {
        
        #; Don't want the session token
        Set %response.OutputSessionToken=0
        
        #; Also set language to prevent any attempt to call %response.MatchLanguage as this can cause PROTECT errors reading from ^IRIS.Msg global
        If %response.Language="" Set %response.Language="en"
        
        Set tMatchURL=$Extract(%request.URL,$Length(%request.Application),*)
      
        #; Process CORS request
        Set tSC=..ProcessCorsRequest(tMatchURL)
        If $$$ISERR(tSC) Quit
            
        If %request.Method="OPTIONS" {
            
            #; We want to allow OPTIONS requests even if not authorized
            Set tSC=..OnHandleOptionsRequest(tMatchURL)
            If $$$ISERR(tSC) Quit
         
        } else {
            
            #; Set the Http Status
            Set %response.Status=..#HTTP401UNAUTHORIZED
            
            #; We do not want Basic authentication
            #; Do %response.SetHeader("WWW-Authenticate","Basic")
        }
        
    } Catch (e) {
        Set tSC=e.AsStatus()
    }
    
    #; We need to manually write out the headers here because PAGE has not been called
    Do %response.WriteHTTPHeader()
        
    #; Done
    Quit tSC
}

/// This method takes a status, renders it as json (if requested) and outputs the result
ClassMethod outputStatus(pSC As %Status) As %Status [ Internal ]
{
    #dim tSC As %Status = $$$OK
    #dim e As %Exception.AbstractException
    
    try {
        
        #dim tJSON As %ZEN.proxyObject
    
        if ..AcceptsContentType("application/json") {
        
            set %response.ContentType = ..#CONTENTTYPEJSON
        
            #; Convert the exception to a status and render to JSON
            set tSC = ..StatusToProxyObject(pSC, .tJSON)
            set tJSON.stack = ..getDebugInfo()
            if $$$ISERR(tSC) Quit

            #; Write the JSON to the output device
            set tSC = tJSON.%ToJSON(, "aeloqutwc")
            if $$$ISERR(tSC) Quit
            
        } else {
            
            #; Set plain text
            set %response.ContentType = ..#CONTENTTYPETEXT
            
            #; Write out a simple text message
            do ##class(%Exception.StatusException).CreateFromStatus(pSC).OutputToDevice()
        }
        
    } catch ex {
        set tSC = ex.AsStatus()
    }
    quit $$$OK
}

ClassMethod getDebugInfo() As %ZEN.proxyObject
{
	set obj = ##class(%ZEN.proxyObject).%New()
	set obj.stack = ..getStackInfo()
	set obj.objlasterror = $system.Status.GetErrorText($get(%objlasterror))
	set obj.request = %request
	set obj.response = %response
	set obj.user = $username
	
	quit obj
}

ClassMethod getStackInfo() As %ListOfDataTypes
{

	set ex = ##class(%Exception.SystemException).%New()
	do ex.StackAsArray(.stack)
	set list = ##class(%ListOfObjects).%New()
	for i=1:1:stack {
		set obj = ##class(%ZEN.proxyObject).%New()
		set obj.line = stack(i,"PLACE")
		set obj.call =  stack(i)
		set obj.part = $piece($piece(stack(i,"PLACE"), "^", *), " ", 1)
		do list.Insert(obj)
	}
	
	quit list
}

/// Get user info
ClassMethod getUserInfo() As %Status
{
	#dim %session As %CSP.Session
	set user = {
		"username": ($Username),
		"timeout": (%session.AppTimeout)
	}
	write user.%ToJSON()
	quit $$$OK
}

}

