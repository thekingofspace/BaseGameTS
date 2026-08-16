--!strict
return table.freeze({
    PIGEON_NAME = "ReplicationPP",
    RECEIVER_NAME = "ReplicationPP_Receiver",
    ASSETS_NAME = "ReplicationPP_Assets",

    ATTR_ID = "ReplicationPP_Id",
    ATTR_DESCENDANTS = "ReplicationPP_Descendants",

    MSG_CLAIM = "@ReplicationPP/Claim",
    MSG_REMOVE = "@ReplicationPP/Remove",
    MSG_REVOKE = "@ReplicationPP/Revoke",
})
