
class TestViewController < UIViewController

  def viewDidLoad
    puts "viewDidLoad"
    self.navigationItem.rightBarButtonItem = 
      UIBarButtonItem.alloc.initWithTitle:"Join", 
        style:UIBarButtonItemStyleBordered,
        target:self,
        action:'joinChat'
    @photos = NSMutableArray.alloc.initWithCapacity(0)

    @connect = "tcp://localhost:5555"
    @retries = 3
    @timeout = 10
    @ctx = ZMQ::Context.new
    client_sock
    @poller = ZMQ::Poller.new
    @poller.register_readable @socket 
    at_exit do
      @socket.close
    end
  end

  def client_sock
    @socket = @ctx.socket(ZMQ::REQ)
puts "in client_sock: before set, getsockopt LINGER = #{@socket.getsockopt(ZMQ::LINGER)}"
    @socket.setsockopt(ZMQ::LINGER, 0)
puts "in client_sock: after set, getsockopt LINGER = #{@socket.getsockopt(ZMQ::LINGER)}"
    @socket.setsockopt(ZMQ::LINGER, -1)
    rc = @socket.connect(@connect)
    unless ZMQ::Util.resultcode_ok?(rc)
puts "in client_sock error: #{ZMQ::Util.errno}, #{ZMQ::Util.error_string}"
    else
puts "connect succeeded #{rc}"
    end
  end

  def joinChat
    sequence = 0
    retries_left = 3
    while retries_left > 0
      request = "#{sequence}"
      sequence += 1
      @socket.send_nsdata "#{sequence}".dataUsingEncoding(NSASCIIStringEncoding)
puts "in JOIN socket addr: #{loklok(@socket.socket)}"
      expect_reply = 1
      while expect_reply > 0
        @poller.poll 2500 # 2.5 secs
        if @poller.readables.size > 0
          @poller.readables.each do |s|
	    nsdata = s.recv_nsdata
	    if nsdata.nil?
	      break
	    end
	    reply = NSString.alloc.initWithData(nsdata, encoding:NSASCIIStringEncoding).to_i
	    if reply == sequence
	      puts "I: server replied OK #{sequence}"
	      retries_left = 3
              expect_reply = 0
	    else
	      puts "E: malformed reply from server: #{reply}"
	    end
	  end
        else
          retries_left -= 1
          if retries_left == 0
            puts "E: server seems to be offline, abandoning"
            break # we're stoping
          else
            puts "W: no response from server, retrying..."
            @socket.close
            @poller.delete @socket
            puts "I: reconnecting to server..."
            client_sock
            @poller.register_readable @socket
            @socket.send_nsdata "#{sequence}".dataUsingEncoding(NSASCIIStringEncoding)
puts "in JOIN socket addr: #{loklok(@socket.socket)}"
          end
        end
      end
    end

    # chat client approach
    #@online_session = OnlineSession.alloc.initWithHost:"nandalu.idv.tw", port:7777
    #@online_session.delegate = self
    #@online_session.sendData("\x010004room0002YY".dataUsingEncoding(NSUTF8StringEncoding))
  end

  def find_photos indices
    # photos is an array of NSData*
    @photos.removeAllObjects
    ALAssetsLibrary.alloc.init.enumerateGroupsWithTypes(ALAssetsGroupSavedPhotos,
      usingBlock: lambda do |group, stop|
        break if !group
        group.enumerateAssetsAtIndexes(indices, 
          options:NSEnumerationReverse, 
          usingBlock: lambda do |result, index, stop|
            next if index == NSNotFound || index == -1
            @photos.addObject(UIImageJPEGRepresentation(
	      UIImage.imageWithCGImage(result.defaultRepresentation.fullResolutionImage),
              1.0))
          end
        )
        d = NSMutableData.dataWithCapacity(0)
        d.appendData("\x030004room0002YY".dataUsingEncoding(NSUTF8StringEncoding))
        d.appendData(encode64ToNSData(@photos[0]))
        @online_session.sendData(d)
      end,
      failureBlock: lambda do |err|
        puts err.localizedDescription
      end
    )
  end

  def onlineSession(session, receivedData:data)
    puts "received data..."
    sdata = NSString.alloc.initWithData(data, encoding:NSUTF8StringEncoding)
    puts sdata

    # test server response
    if sdata == "fumin: GET"
      find_photos(intArrayToNSIndexSet([0]))
    end
  end

  def intArrayToNSIndexSet array
    i = NSMutableIndexSet.indexSet
    array.map do |e| 
      return NSMutableIndexSet.indexSet if !e.is_a?(Integer)
      i.addIndex(e)
    end
    return i
  end

  def encode64ToNSData bin
    [bin].pack("m").dataUsingEncoding(NSASCIIStringEncoding)
  end

  def onlineSession(session, encounteredReadError:error)
    puts error
  end

  def onlineSession(session, encounteredWriteError:error)
    puts error
  end

  def sendMessage
    @online_session.sendData("\x0300000004rooma_message")
  end

end
