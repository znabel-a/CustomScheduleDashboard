Import-Module FreshServicePS

function Get-FSScheduleInfo {
    return Get-PSUSchedule | Where-Object { $_.name -like "?OC?*"} | select-object description,id,cron,delay,environment,script,paused,parameters,
         @{n="Name";e={ ($_.name.split(" "))[1..($_.name.split(" ").length)] -join " " }},
         @{n="nextExecution";e={ (Get-Date -date $_.nextExecution).ToLocalTime().toString("dddd dd MMMM HH:mm")  }},
         @{n="daysTo";e={ [math]::Ceiling(  (New-TimeSpan -Start (get-date) -End (Get-Date $_.nextExecution).ToLocalTime()).TotalDays )  }}
}

$RefreshInterval = 15
$Schedule        = New-UDEndpointSchedule -Every $RefreshInterval -Minute

New-UDEndpoint -Schedule $Schedule -Endpoint {
    $cache:dataSCH = Get-FSScheduleInfo | sort-object daysTo,name -Descending
    $cache:timeSCH = Get-Date
} | Out-Null

$ticketFields = Get-FSTicket -fields

$ColumnsSCH =@(
    New-UDTableColumn -Property id              -Title 'Schedule ID'        -Hidden
    New-UDTableColumn -Property name            -Title 'Schedule Name'      -IncludeInExport -IncludeInSearch -Truncate
    New-UDTableColumn -Property nextExecution   -Title 'Next Execution'     -IncludeInExport -Truncate -Render {
       if ( $EventData.nextExecution ) { $EventData.nextExecution }
       else {
            New-UDIcon -Icon PauseCircle
            " Paused"
       }
    } -IncludeInSearch
    New-UDTableColumn -Property daysTo          -Title 'In # Days'     -IncludeInExport -Truncate -Align center
    New-UDTableColumn -Property description     -Title 'CRON Description'   -IncludeInExport -Truncate -Render {
        if ( $EventData.nextExecution ) { $EventData.description }
    }
    New-UDTableColumn -Property Edit -Title 'Edit' -Truncate -ShowSort $false -Render {
        New-UDButton -Id "btn_edit_$($EventData.id)" -OnClick {
            Show-UDModal -Content {
                New-UDForm -id "frm_$($eventData.id)" -Content {
                    New-UDElement -Tag 'div' -Endpoint { "Edit schedule" }
                    New-UDElement -Tag 'hr'
                    New-UDTextbox -Label "Name" -Value $EventData.name -Id "tb_name_$($eventData.id)" -FullWidth
                    New-UDTextbox -Label "Description" -Value $( [System.Web.HttpUtility]::HtmlDecode(
                                [System.Management.Automation.PSSerializer]::Deserialize(
                                    $($eventData.Parameters | where-object { $_.name -eq "ticketdescription" } ).value
                                )
                            ).replace("<br>","`n")
                        ) -FullWidth -Multiline
                    New-UDTextbox -Label "Schedule CRON" -Value $EventData.cron -Id "tb_cron_$($eventData.id)"
                    New-UDTextbox -Label "Schedule Description" -Value $EventData.description -Id "tb_cron_$($eventData.id)" -FullWidth
                } -SubmitText "Save Schedule" -OnSubmit {
                    Invoke-UDForm -Id "frm_$($eventData.id)" -Verbose
                    Hide-UDModal
                } -CancelText "Cancel Edit" -OnCancel {
                    Hide-UDModal
                }
            } -Persistent
        } -Icon Edit -Variant outlined -Text "" -Style @{ Width = "25px"; Height = "25px" }

        New-UDButton -Id "btn_clone_$($EventData.id)" -OnClick {
            Show-UDToast -Message $(( $EventData | convertto-html -fragment -as List | out-string ) + ( $EventData.parameters | Select-Object name,displayvalue | convertto-html -fragment -as List | out-string ))  -Icon Clone  -Variant outlined -Text "" -Style @{ Width = "25px"; Height = "25px" }
        }

        New-UDButton -Id "btn_delete_$($EventData.id)" -OnClick {
            Show-UDToast -Message ( $ticketFields | convertto-html -fragment -as List | out-string )
            Show-UDModal -Content {
                New-UDElement -Tag 'div' -Endpoint { "Are you sure you want to delete the schedule..." }
                New-UDElement -Tag 'hr'
                New-UDElement -Tag 'div' -Endpoint { $EventData.name }
                New-UDElement -Tag 'div' -Endpoint { $EventData.description }
            } -Persistent -Footer {
                New-UDButton -Text "Yes" -OnClick {
                    Hide-UDModal
                }
                New-UDButton -Text "No" -OnClick {
                    Hide-UDModal
                }
            }
        } -Icon TrashAlt -Variant outlined -Text "" -Style @{ Width = "25px"; Height = "25px" }
    }
)

$Page_1Schedule = New-UDPage -Name "OC" -Icon (New-UDIcon -Icon Home) -Content {
    New-UDTable -Title " Schedules" -id "schedule" -Icon (New-UDIcon -Icon Clock) -Export -ExportOption @("XLSX") -ToolbarContent {
        New-UDTooltip -Content {
            New-UDButton -Id "btn_new_schedule" -OnClick {
            } -Icon Add -Variant outlined -Text "New"
        } -TooltipContent { "Create new schedule" }
     } -Sort -Data $cache:dataSCH -Columns $ColumnsSCH -Dense -ShowSearch -OnRowExpand {
        New-UDhtml -Markup ("<p><b>Ticket description:</b><br>" + [System.Web.HttpUtility]::HtmlDecode(
                [System.Management.Automation.PSSerializer]::Deserialize(
                    $($eventData.Parameters | Where-Object {$_.name -eq "ticketdescription" }).value
                )
            ) +
            "</p><p><b>Ticket contact:</b><br>" + [System.Web.HttpUtility]::HtmlDecode(
                [System.Management.Automation.PSSerializer]::Deserialize(
                   ($eventData.Parameters | Where-Object {$_.name -eq "ticketcontact" }).value
                )
            ) + "</p>"
        )
    }
    New-UDElement -Tag 'div' -Endpoint {
        New-UDhtml -Markup "(c) $(get-date -Format yyyy) DanofficeIT - CRON engine uses <a target='_blank' href='https://docs.hangfire.io/'>Hangfire Core</a> - <a target='_blank' href='https://crontab.guru/'>CRON editor</a> - Data refreshed - $($cache:timeSCH)"
        } -AutoRefresh -RefreshInterval $RefreshInterval -Attributes @{ style = @{ textAlign = 'right' }
    }
}

$Page_2Test = New-UDPage -NAme "OCtest" -Content {
    New-UDTable -Data $cache:dataSCH -Columns $ColumnsSCH -Sort -Dense -ShowSearch -StickyHeader -OnRowExpand {
        New-UDCard -Title "Schedule Description" -Text $([System.Web.HttpUtility]::HtmlDecode($([System.Management.Automation.PSSerializer]::Deserialize(($eventData.Parameters | Where-Object {$_.name -eq "ticketdescription" }).value)))).replace("<br>","`n")
        New-UDCard -Title "Schedule Contact" -Text $([System.Web.HttpUtility]::HtmlDecode($([System.Management.Automation.PSSerializer]::Deserialize(($eventData.Parameters | Where-Object {$_.name -eq "ticketcontact" }).value)))).replace("<br>","`n")

    }
}

$Page_3Test = New-UDpage -name "ScheduledText" -Content {
    New-UDTextbox -id "test" -Multiline -Value $cache:dataSCH[0] -FullWidth
    New-UDTextbox -id "test" -Multiline -Value $cache:dataSCH[0].Parameters -FullWidth
    New-UDTextbox -id "test" -Multiline -Value $([System.Web.HttpUtility]::HtmlDecode($([System.Management.Automation.PSSerializer]::Deserialize(($cache:dataSCH[0].Parameters | Where-Object {$_.name -eq "ticketdescription" }).value)))).replace("<br>","`n") -FullWidth
}

New-UDDashboard -Title "DanofficeIT Operations Center custom Schedules" -Pages @((Get-Variable Page_*).Value) <# -Stylesheets @("/images/squp.css") #> # -DefaultTheme dark

