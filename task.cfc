component {
	property name="progress" inject="progressBarGeneric";

	adobeURIs = [ '/CFIDE/administrator/index.cfm' ];
	luceeURIs = [ '/lucee/admin/server.cfm', '/lucee/admin/web.cfm' ];
	protocolsAll = [ 'https://', 'http://' ];
	protocolsHTTP = [ 'http://' ];

	function run(
		string targetsFile=resolvePath('targets.json'),
		string vendors='all',
		boolean verbose=false
	) {
		job.start( 'Scanning for CFML admins' );

			if( !fileExists( targetsFile ) ) {
				error( 'Targets file [#targetsFile#] doesn''t exist.', 'You may have intended to pass a custom targets.json file' );
			}

			job.start( 'Gathering list of targets' );
				var targets = systemSettings.expandDeepSystemSettings( deserializeJSON( fileRead( targetsFile ) ) )
					.filter( (t)=>!(t.skip?:false) )
					.reduce( (acc,t)=>{
						acc.append( expandAdminPaths( expandProtocols( t.hostname?:[], protocolsAll ), vendors ), true );
						acc.append( expandAdminPaths( expandProtocols( t.ip?:[], protocolsHTTP ), vendors ), true );
						acc.append( expandAdminPaths( t.baseurl?:[], vendors ), true );
						acc.append( t.url?:[], true );
						return acc;
					}, [] );

				job.addLog( 'Found #targets.len()# targets to scan.' );
			job.complete();

			job.start( 'Scanning #targets.len()# targets...', 15 );
				var processedNum = 0;
				progress.update( percent=0 );
				var accessableAdmins = [];
				var start = getTickCount();

				targets.each( (t)=>{
					http url=t result='local.results' timeout=5;
					if( local.results.status_Code == 200 ) {
						accessableAdmins.append( {
							'url' : t,
							'status' : local.results.statusCode,
							'title' : getPageTitle( local.results.fileContent )
						 } );
					}
					lock name="update-progress-bar" type="exclusive" timeout=20 {
						job.addLog( 'Scanning [#t#]...' );
						if( verbose ) {
							job[ 'add#( local.results.status_Code == 200 ? 'Error' : 'Success' )#Log' ]( local.results.statusCode );
						}
						processedNum++;
						progress.update( percent=(processedNum/targets.len()) * 100, currentCount=processedNum, totalCount=targets.len() );
					}

				}, true );
				
			progress.clear();
			job.addLog( 'Completed in #getTickCount()-start#ms' )
			job.complete();
			
		job.complete( verbose );

		if( accessableAdmins.len() ) {
			setExitCode( 1 );
			print
				.line()
				.redLine( 'Accessable admins found!' )
				.line();
			accessableAdmins.each( (t)=> {
				print
					.indentedLine( t.url )
					.indentedIndentedLine( t.status & ( len(t.title) ? ' (#t.title#)' : '' ) )
					.line() 
				} );
		}
		

	}

	array function expandProtocols( required array targets, required array protocols ) {
		return targets.reduce( (acc,t)=>acc.append( protocols.map((p)=>p&t), true ), [] );
	}

	array function expandAdminPaths( required array targets, required string vendors ) {
		return targets.reduce( (acc,t)=>{
			if( 'all,adobe'.listFindNoCase( vendors ) ) {
				acc.append( adobeURIs.map((u)=>t&u), true );
			}
			if( 'all,lucee'.listFindNoCase( vendors ) ) {
				acc.append( luceeURIs.map((u)=>t&u), true );
			}
			return acc;
		}, [] );
	}

	string function getPageTitle( required string fileContent ) {
		var html = HTMLParse( fileContent );
		var titleSearch = xmlSearch( html, '//title' );
		if( !titleSearch.len() ) {
			titleSearch = xmlSearch( html, '//:title' );
		}
		if( titleSearch.len() ) {
			return titleSearch[1].XMLText;
		}
		return '';
	}

}
