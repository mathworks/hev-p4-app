classdef (ConstructOnLoad) NotifyData < event.EventData
   properties
      Data
   end
   
   methods
       function obj = NotifyData(Input)
         obj.Data = Input;
      end
   end
end