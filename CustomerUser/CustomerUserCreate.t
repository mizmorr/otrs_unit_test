# Copyright (C) 2001-2020 OTRS AG, https://otrs.com/
# Copyright (C) 2021 Centuran Consulting, https://centuran.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

## no critic (Modules::RequireExplicitPackage)
use strict;
use warnings;
use utf8;
use vars (qw($Self));
use Kernel::GenericInterface::Debugger;
use Kernel::GenericInterface::Operation::Session::SessionCreate;
use Kernel::GenericInterface::Operation::Customer::CustomerUserCreate;
my $CustomerUserObject  = $Kernel::OM->Get('Kernel::System::CustomerUser');
my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
my $CacheObject	 = $Kernel::OM->Get('Kernel::System::Cache');

# Skip SSL certificate verification.
$Kernel::OM->ObjectParamAdd(
    'Kernel::System::UnitTest::Helper' => {
        SkipSSLVerify => 1,
    },
);

my $Helper      = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');
my $RandomID = $Helper->GetRandomNumber();

my $UserObject = $Kernel::OM->Get('Kernel::System::User');

$Helper->ConfigSettingChange(
    Valid => 1,
    Key   => 'CheckEmailAddresses',
    Value => 0,
);

# disable SessionCheckRemoteIP setting
$Helper->ConfigSettingChange(
    Valid => 1,
    Key   => 'SessionCheckRemoteIP',
    Value => 0,
);

# enable customer groups support
$Helper->ConfigSettingChange(
    Valid => 1,
    Key   => 'CustomerGroupSupport',
    Value => 1,
);

#create user for tests

my $TestUserLogin         = $Helper->TestUserCreate(
    Groups => [ 'admin', 'users', ],
);

my $UserID = $UserObject->UserLookup(
    UserLogin => $TestUserLogin,
);

$Self->True(
    $UserID,
    'User Add ()',
);

#delete old customer users

my @OldCustomerUserIDs = $CustomerUserObject->CustomerSearch(
        CustomerID => '*-Customer-Id-Test',
        ValidID    => 1,
);

for my $CustomerUserID (@OldCustomerUserIDs) {
        $CustomerUserObject->CustomerUserDelete(
                CustomerUserID  => $CustomerUserID,
                UserID          => 1,
	);
}


# create web service

my $WebserviceName = '-Test-' . $RandomID;
my $WebserviceObject = $Kernel::OM->Get('Kernel::System::GenericInterface::Webservice');
$Self->Is(
        'Kernel::System::GenericInterface::Webservice',
        ref $WebserviceObject,
        "Create web service object"
);
my $WebserviceID = $WebserviceObject->WebserviceAdd(
    Name   => $WebserviceName,
    Config => {
        Debugger => {
            DebugThreshold => 'debug',
        },
        Provider => {
            Transport => {
                Type => '',
            },
        },
    },
    ValidID => 1,
    UserID  => 1,
);
$Self->True(
    $WebserviceID,
    'Added web service'
);
my $Host = $Helper->GetTestHTTPHostname();
my $RemoteSystem =
    $ConfigObject->Get('HttpType')
    . '://'
    . $Host
    . '/'
    . $ConfigObject->Get('ScriptAlias')
    . '/nph-genericinterface.pl/WebserviceID/'
    . $WebserviceID;
my $WebserviceConfig = { 
        Description =>
                'Test for CustomerUser Connector using SOAP transport backend.',
        Debugger => {
                DebugThreshold  => 'debug',
                TestMode        => 1,
        },
        Provider => {
                Transport => {
                        Type => 'HTTP::SOAP',
                        Config => {
                                MaxLenght => 10000000,
                                NameSpace => 'http://otrs.org/SoapTestInterface/',
                                Endpoint  => $RemoteSystem,
                        },
                },
                Operation => {
                        CustomerUserCreate => {
                                Type => 'Customer::CustomerUserCreate',
                        },
                        SessionCreate => {
                                Type => 'Session::SessionCreate',
                        },
                },
},
        Requester => {
                Transport => {
                        Type    => 'HTTP::SOAP',
                        Config  => {
                                NameSpace => 'http://otrs.org/SoapTestInterface/',
                                Encodiong => 'UTF-8',
                                Endpoint  =>  $RemoteSystem,
                                Timeout   =>  120,
                        },
                },
                Invoker => {
                        CustomerUserCreate => {
                                Type => 'Test::TestSimple',
                        },
                        SessionCreate => {
                                Type => 'Test::TestSimple',
                        },
                },
        },

};

# update web-service with real config
# the update is needed because we are using
# the WebserviceID for the Endpoint in config

my $WebserviceUpdate = $WebserviceObject->WebserviceUpdate(
	ID      => $WebserviceID,
        Name    => $WebserviceName,
        Config  => $WebserviceConfig,
        ValidID => 1,
        UserID  => $UserID,
);

$Self->True(
        $WebserviceUpdate,
        "Updated web service $WebserviceID - $WebserviceName" 
);

# Get SessionID
# create requester object
my $RequesterSessionObject = $Kernel::OM->Get('Kernel::GenericInterface::Requester');
$Self->Is(
    'Kernel::GenericInterface::Requester',
    ref $RequesterSessionObject,
    'SessionID - Create requester object'
);

my $UserLogin = $Helper->TestUserCreate(
        Groups => ['admin','users'],
);

my $Password = $UserLogin;

# start requester with our web service
my $RequesterSessionResult = $RequesterSessionObject->Run(
    WebserviceID => $WebserviceID,
    Invoker      => 'SessionCreate',
    Data         => {
        UserLogin => $UserLogin,
        Password  => $Password,
    },
);

my $NewSessionID = $RequesterSessionResult->{Data}->{SessionID};

my $Key = 'Special';

my $SpecialCustomerUser = $CustomerUserObject->CustomerUserAdd(
        Source         => 'CustomerUser',
        UserFirstname  => 'Firstname Test' . $Key,
        UserLastname   => 'Lastname Test' . $Key,
        UserCustomerID => $Key . '-Customer-Id',
        UserLogin      => $Key,
        UserEmail      => $Key . '-Email@example.com',
        UserPassword   => 'some_pass',
        ValidID        => 1,
        UserID         => 1,
);

$Self->True(
       $SpecialCustomerUser,
       "CustomerUser is created with ID $SpecialCustomerUser",
);

#$Helper->ConfigSettingChange(
#    Valid => 1,
#    Key   => 'CheckEmailAddresses',
#    Value => 1,
#);


my @Tests = 
(
    {
        Name           => 'Empty Request',
        SuccessRequest => 1,
        SuccessCreate  => 0,
        RequestData    => {},
        ExpectedData   => {
            Data => {
                Error => {
                    ErrorCode	 => 'CustomerUserCreate.MissingParameter',
		    ErrorMessage => "CustomerUserCreate: CustomerUser  parameter is missing or not valid!",
                },
            },
            Success => 1
        },
        Operation => 'CustomerUserCreate',
    }, 

    {
        Name           => 'Invalid CustomerUser',
        SuccessRequest => 1,
        SuccessCreate  => 0,
        RequestData    => {
		CustomerUser => 1,
	},
        ExpectedData   => {
            Data => {
                Error => {
                    ErrorCode	 => 'CustomerUserCreate.MissingParameter',
		    ErrorMessage => "CustomerUserCreate: CustomerUser  parameter is missing or not valid!",
                },
            },
            Success => 1
        },
        Operation => 'CustomerUserCreate',
    },

    {
        Name           => 'Invalid DynamicField',
        SuccessRequest => 1,
        SuccessCreate  => 0,
        RequestData    => {
		CustomerUser => {
			Test => 1,
		},
		DynamicField => 1,
	},
        ExpectedData   => {
            Data => {
                Error => {
                    ErrorCode	 => 'CustomerUserCreate.MissingParameter',
		    ErrorMessage => "CustomerUserCreate: CustomerUser  parameter is missing or not valid!",
                },
            },
            Success => 1
        },
        Operation => 'CustomerUserCreate',
    },

    {
        Name           => 'Missing lastname',
        SuccessRequest => 1,
        SuccessCreate  => 0,
        RequestData    => {
		CustomerUser => {
			UserLogin => 'ValidLogin',
		},
	},
        ExpectedData   => {
            Data => {
                Error => {
                    ErrorCode    => 'CustomerUserCreate.MissingParameter',
                    ErrorMessage => "CustomerUserCreate: UserLastname parameter is missing!",

		},
            },
            Success => 1
        },
        Operation => 'CustomerUserCreate',
    },

   {
        Name           => 'Missing email',
        SuccessRequest => 1,
        SuccessCreate  => 0,
        RequestData    => {
		CustomerUser => {
			UserLogin => 'ValidLogin',
			UserLastname => 'ValidLastname',
		},
	},
        ExpectedData   => {
            Data => {
                Error => {
                    ErrorCode    => 'CustomerUserCreate.MissingParameter',
                    ErrorMessage => "CustomerUserCreate: UserEmail parameter is missing!",

		},
            },
            Success => 1
        },
        Operation => 'CustomerUserCreate',
    },

    {
        Name           => 'Missing Firstname',
        SuccessRequest => 1,
        SuccessCreate  => 0,
        RequestData    => {
		CustomerUser => {
			UserLogin => 'ValidLogin',
			UserLastname => 'ValidLastname',
			UserEmail    => 'validemail-Email@example.com',
		},
	},
        ExpectedData   => {
            Data => {
                Error => {
                    ErrorCode    => 'CustomerUserCreate.MissingParameter',
                    ErrorMessage => "CustomerUserCreate: UserFirstname parameter is missing!",

		},
            },
            Success => 1
        },
        Operation => 'CustomerUserCreate',
    },

   {
        Name           => 'Bad source',
        SuccessRequest => 1,
        SuccessCreate  => 0,
        RequestData    => {
		CustomerUser => {
			Source		=> 'NotCustomerUser',	  
			UserLogin	=> 'ValidLogin',
			UserLastname	=> 'ValidLastname',
			UserEmail	=> 'validemail-Email@example.com',
			UserFirstname	=> 'ValidFirstname',
		},
	},
        ExpectedData   => {
            Data => {
                Error => {
                    ErrorCode    => 'CustomerUserCreate.ValidateSource',
                    ErrorMessage => "CustomerUserCreate: Source is invalid!",
		},
            },
            Success => 1
        },
        Operation => 'CustomerUserCreate',
    },
 
    {
        Name           => 'UserLogin already exist',
        SuccessRequest => 1,
        SuccessCreate  => 0,
        RequestData    => {
		CustomerUser => {
			UserLogin	=> $Key,
			UserLastname	=> 'ValidLastname',
			UserEmail	=> 'validemail-Email@example.com',
			UserFirstname	=> 'ValidFirstname',
		},
	},
        ExpectedData   => {
            Data => {
                Error => {
                    ErrorCode    => 'CustomerUserCreate.ValidateUserLogin',
                    ErrorMessage => "CustomerUserCreate: UserLogin already exist!",
		},
            },
            Success => 1
        },
        Operation => 'CustomerUserCreate',
    },
 
    {
        Name           => 'Invalid email',
        SuccessRequest => 1,
        SuccessCreate  => 0,
        RequestData    => {
		CustomerUser => {
			UserLogin	=> 'ValidLogin',
			UserLastname	=> 'ValidLastname',
			UserEmail	=> 'Invalid' . '-Email@example.com',
			UserFirstname	=> 'ValidFirstname',
		},
	},
        ExpectedData   => {
            Data => {
                Error => {
                    ErrorCode    => 'CustomerUserUpdate.EmailValidate',
                    ErrorMessage => "CustomerUserUpdate: Email address not valid!",
		},
            },
            Success => 1
        },
        Operation => 'CustomerUserCreate',
    },

    {
        Name           => 'Email in use',
        SuccessRequest => 1,
        SuccessCreate  => 0,
        RequestData    => {
		CustomerUser => {
			UserLogin	=> 'ValidLogin',
			UserLastname	=> 'ValidLastname',
			UserEmail	=> $Key . '-Email@example.com',
			UserFirstname	=> 'ValidFirstname',
		},
	},
	#todo : should return error email in use
        ExpectedData   => {
            Data => {
                Error => {
                    ErrorCode    => 'CustomerUserUpdate.EmailValidate',
                    ErrorMessage => "CustomerUserUpdate: Email address already in use for another customer user!",
		},
            },
            Success => 1
        },
        Operation => 'CustomerUserCreate',
    },

	 
);
my $DebuggerObject = Kernel::GenericInterface::Debugger->new(
        DebuggerConfig => {
                DebugThreshold  => 'debug',
                TestMode        => 1,
        },
        WebserviceID            => $WebserviceID,
        CommunicationType       => 'Provider',
);
$Self->Is(
        ref $DebuggerObject,
        'Kernel::GenericInterface::Debugger',
        'DebuggerObject instantiate correctly'
);

for my $Test (@Tests) {
            if ( $Test->{Type} eq 'EmailCustomerUser' ) {
                $Helper->ConfigSettingChange(
                    Valid => 1,
                    Key   => 'CheckEmailAddresses',
                    Value => 0,
                );
            }
            else {
                $Helper->ConfigSettingChange(
                    Valid => 1,
                    Key   => 'CheckEmailAddresses',
                    Value => 1,
                );
            }	   
	   # create local object
	    my $LocalObject = "Kernel::GenericInterface::Operation::Customer::$Test->{Operation}"->new(
	        DebuggerObject => $DebuggerObject,
	        WebserviceID   => $WebserviceID,
	    );

	    $Self->Is(
	        "Kernel::GenericInterface::Operation::Customer::$Test->{Operation}",
	        ref $LocalObject,
	        "$Test->{Name} - Create local object"
	    );

    my %Auth = (
        UserLogin => $UserLogin,
        Password  => $Password,
    );

    # start requester with our web service
    my $LocalResult = $LocalObject->Run(
        WebserviceID => $WebserviceID,
        Invoker      => $Test->{Operation},
        Data         => {
            %Auth,
            %{ $Test->{RequestData} },
        },
    );

    # check result
    $Self->Is(
        'HASH',
        ref $LocalResult,
        "$Test->{Name} - Local result structure is valid"
    );

    # create requester object
    my $RequesterObject = $Kernel::OM->Get('Kernel::GenericInterface::Requester');
    $Self->Is(
        'Kernel::GenericInterface::Requester',
        ref $RequesterObject,
        "$Test->{Name} - Create requester object"
    );

    # start requester with our web service
    my $RequesterResult = $RequesterObject->Run(
        WebserviceID => $WebserviceID,
        Invoker      => $Test->{Operation},
        Data         => {
            %Auth,
            %{ $Test->{RequestData} },
        },
    );

    
   # check result
   
    $Self->Is(
        'HASH',
        ref $RequesterResult,
        "$Test->{Name} - Requester result structure is valid"
    );

    $Self->Is(
        $RequesterResult->{Success},
        $Test->{SuccessRequest},
        "$Test->{Name} - Requester successful result"
    );

    if ( $Test->{SuccessCreate} ) {

    }

    else {
	
        $Self->Is(
            $LocalResult->{Data}->{Error}->{ErrorCode},
            $Test->{ExpectedData}->{Data}->{Error}->{ErrorCode},
            "$Test->{Name} - Local result ErrorCode matched with expected local call result."
        );
        $Self->True(
            $LocalResult->{Data}->{Error}->{ErrorMessage},
            "$Test->{Name} - Local result ErrorMessage with true."
        );
        $Self->IsNot(
            $LocalResult->{Data}->{Error}->{ErrorMessage},
            '',
            "$Test->{Name} - Local result ErrorMessage is not empty."
        );

        $Self->Is(
            $LocalResult->{ErrorMessage},
            $LocalResult->{Data}->{Error}->{ErrorCode}
                . ': '
                . $LocalResult->{Data}->{Error}->{ErrorMessage},
            "$Test->{Name} - Local result ErrorMessage (outside Data hash) matched with concatenation"
                . " of ErrorCode and ErrorMessage within Data hash."
        );

        # remove ErrorMessage parameter from direct call
        # result to be consistent with SOAP call result
        if ( $LocalResult->{ErrorMessage} ) {
            delete $LocalResult->{ErrorMessage};
        }
       
	# sanity check
        $Self->False(
            $LocalResult->{ErrorMessage},
            "$Test->{Name} - Local result ErrorMessage (outside Data hash) got removed to compare"
                . " local and remote tests."
        );

        $Self->IsDeeply(
            $LocalResult,
            $RequesterResult,
            "$Test->{Name} - Local result matched with remote result."
        );

    }

}
# clean up

my $WebserviceDelete = $WebserviceObject->WebserviceDelete(
	ID	=>	$WebserviceID,
	UserID	=>	$UserID,
);

$Self->True(
	$WebserviceDelete,
	"Deleted web service $WebserviceID",
);
 
# delete customer users

my $CustomerUserDelete = $CustomerUserObject->CustomerUserDelete(
		CustomerUserID	=> $SpecialCustomerUser,
		UserID		=> $UserID,
	);

$Self->True(
	$CustomerUserDelete,
	"CustomerUserDelete() successful for CustomerUser ID $SpecialCustomerUser",
);


# delete user
my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
 
my $Success = $DBObject->Do(
    SQL => "DELETE FROM user_preferences WHERE user_id = $UserID",
);
$Self->True(
    $Success,
    "User preference referenced to User ID $UserID is deleted!"
);
#$Success = $DBObject->Do(
#    SQL => "DELETE FROM users WHERE id = $UserID",
#);
#$Self->True(
#    $Success,
#    "User with ID $UserID is deleted!"
#);

$CacheObject->CleanUp();
	
1;


